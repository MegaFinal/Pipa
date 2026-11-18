//
//  SharedFileReader.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/11/26.
//

import UIKit
import PDFKit
import ImageIO

/// Reads photos and PDFs shared to Pipa (Premium): opens them as page images and tells a
/// receipt from a recipe by their text, with plain code.
///
/// - A receipt goes to the usual receipt review (``ReceiptReviewView``).
/// - A recipe gives its ingredient lines, which become shopping cards in ``SharedImportView``.
nonisolated enum SharedFileReader {

    // MARK: - Pages

    /// One image per photo and per PDF page, at most ``SharedInbox/maxFiles``, shrunk to
    /// `maxSide` pixels so several pages fit in memory (enough for the text to be read).
    static func pages(from urls: [URL], maxSide: CGFloat = 2200) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            var pages: [UIImage] = []
            for url in urls where pages.count < SharedInbox.maxFiles {
                if url.pathExtension.lowercased() == "pdf" {
                    guard let document = PDFDocument(url: url) else { continue }
                    let count = min(document.pageCount, SharedInbox.maxFiles - pages.count)
                    for index in 0..<count {
                        guard let page = document.page(at: index) else { continue }
                        let bounds = page.bounds(for: .mediaBox)
                        let longest = max(bounds.width, bounds.height)
                        guard longest > 0 else { continue }
                        let scale = min(maxSide / longest, 3)
                        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                        pages.append(page.thumbnail(of: size, for: .mediaBox))
                    }
                } else if let image = downsampledImage(at: url, maxSide: maxSide) {
                    pages.append(image)
                }
            }
            return pages
        }.value
    }

    /// The photo at `url`, already turned upright and no bigger than `maxSide`, without
    /// decoding the full-size image first.
    private static func downsampledImage(at url: URL, maxSide: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - Receipt or recipe

    /// Words printed on Brazilian receipts (and a few in other languages), folded and uppercased.
    private static let receiptWords = [
        "CNPJ", "CUPOM FISCAL", "NFC-E", "NFCE", "DANFE", "DOCUMENTO AUXILIAR", "VALOR A PAGAR",
        "SUBTOTAL", "TROCO", "CONSUMIDOR", "CHAVE DE ACESSO", "RECEIPT", "TICKET", "FACTURA"
    ]

    /// A receipt: one of its typical words, or many prices ("12,90") on the page. Recipes have
    /// amounts too, but not prices.
    static func looksLikeReceipt(_ text: String) -> Bool {
        let upper = text.folding(options: [.diacriticInsensitive], locale: nil).uppercased()
        if receiptWords.contains(where: upper.contains) { return true }
        return ReceiptTotals.amountCount(in: text) >= 5
    }

    // MARK: - Orders and invoices

    /// Rows that aren't products: headers, totals, fees and payment.
    private static var notProductRow: some RegexComponent {
        #/(?i)\b(sub\s*total|total|taxa|frete|entrega|desconto|pagamento|pago|troco|cupom|pedido|produto|descri[cç][aã]o|qtd|quantidade|valor|cart[aã]o|pix|saldo|cnpj|cpf)\b/#
    }

    /// Products of an order or invoice laid out as a table (an online supermarket order, a
    /// delivery bill), for when the receipt parser, made for printed receipts, finds none.
    /// Each row with a name and a price at the end is one product; the price is the line's total.
    static func orderLines(in text: String) -> [ReceiptScanLine] {
        // "Tomate italiano   1 kg   R$ 9,90": name, optional amount, then the price at the end.
        // Local, so the named captures keep their types.
        let productRow = #/^(?<name>.*?\p{L}.*?)\s+(?:(?<amount>\d+(?:[.,]\d+)?)\s*(?<unit>kg|g|un|und|unid|x|pc|pct)?\.?\s+)?(?:R\$\s*)?(?<price>\d{1,3}(?:\.\d{3})*,\d{2})\s*$/#.ignoresCase()
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.firstMatch(of: notProductRow) == nil }
            .compactMap { row -> ReceiptScanLine? in
                guard let match = row.wholeMatch(of: productRow),
                      let price = Double(String(match.price).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")),
                      price > 0
                else { return nil }
                let name = String(match.name).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-–·:")))
                guard name.count >= 2 else { return nil }

                let amount = match.amount.flatMap { Double(String($0).replacingOccurrences(of: ",", with: ".")) }
                let unit = match.unit.map { String($0).lowercased() }
                var quantity = 1
                var weightKg = 0.0
                switch (amount, unit) {
                case let (value?, "kg"?): weightKg = value
                case let (value?, "g"?): weightKg = value / 1000
                // Same top as the quantity stepper (``QuantityStepper/allowedRange``).
                case let (value?, _): quantity = max(1, min(Int(value.rounded()), 1000))
                default: break
                }
                return ReceiptScanLine(name: name, quantity: quantity, weightKg: weightKg, total: price)
            }
    }

    /// Titles that start the ingredients, folded and lowercased.
    private static let ingredientTitles = [
        "ingrediente", "ingredient", "ingrédient", "材料", "配料", "食材", "用料", "재료"
    ]

    /// Titles that end them (the method).
    private static let methodTitles = [
        "modo de preparo", "modo de fazer", "preparo", "como fazer", "instru", "preparation",
        "method", "directions", "steps", "preparacion", "elaboracion",
        "作り方", "做法", "步骤", "만드는", "조리"
    ]

    /// Typical ingredient lines when the recipe has no titles: amounts, measures, "a gosto".
    private static var ingredientHint: some RegexComponent { #/^\s*(?:[-•*·]\s*)?(?:\d|½|¼|¾|⅓|meia|meio|uma?\s|dois|duas|tr[eê]s|a gosto|pitada)|x[ií]cara|colher|\bg\b|\bkg\b|\bml\b|litro|a gosto|lata|pacote|dente/#.ignoresCase() }

    /// The ingredient lines of a recipe: what's under "Ingredientes" until "Modo de preparo", or,
    /// without those titles, the lines that look like ingredients.
    static func ingredientLines(in text: String) -> [String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let folded = lines.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

        if let start = folded.firstIndex(where: { line in ingredientTitles.contains { line.hasPrefix($0) } }) {
            let rest = folded.index(after: start)..<folded.endIndex
            let end = rest.first { index in methodTitles.contains { folded[index].hasPrefix($0) } } ?? folded.endIndex
            return Array(lines[folded.index(after: start)..<end])
        }
        return lines.filter { $0.firstMatch(of: ingredientHint) != nil }
    }
}
