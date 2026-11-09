//
//  ReceiptPhotoReader.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation
import FoundationModels
import UIKit

// Reading a receipt photo with the on-device model, together with Vision's text of the same
// photo ("Foto + OCR" on the test bench). Only ``ReceiptScanService`` uses it, and only when
// the parser's sum doesn't match the receipt.
//
// Photos as model input need the iOS 27 SDK. `#if compiler(>=6.4)` (Xcode 27) keeps this file
// building on Xcode 26, where the photo step simply never runs; `@available` keeps it off
// iPhones still on iOS 26.

/// Whether the photo reading can run on this iPhone: iOS 27 with Apple Intelligence ready.
nonisolated enum ReceiptPhotoReading {
    static var isAvailable: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return ReceiptPhotoReader.isAvailable
        }
        #endif
        return false
    }

    /// Reads one page, or returns `nil` when the model can't run or fails.
    ///
    /// - Parameter ocrText: Vision's plain text of the same photo
    ///   (``ReceiptTextReader/Style/plain``).
    static func read(_ image: UIImage, ocrText: String) async -> [ReceiptScanLine]? {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return try? await ReceiptPhotoReader.read(image, ocrText: ocrText)
        }
        #endif
        return nil
    }

    /// Most OCR characters sent with the photo, to stay inside the model's context window. A
    /// longer page isn't sent at all (a long supermarket receipt is the parser's job).
    static let maxOCRCharacters = 2500
}

#if compiler(>=6.4)

/// One purchased product, as printed on the receipt. Properties are generated in declaration
/// order, so the name comes first and the price last.
@available(iOS 27.0, *)
@Generable
nonisolated struct GeneratedReceiptLine {
    @Guide(description: "Product name as printed, without the item number or the product code")
    var name: String

    @Guide(description: "Units bought. 1 when the product is sold by weight", .range(1...999))
    var quantity: Int

    @Guide(description: "Weight in kilograms, only when the product's line shows a weight followed by KG. 0 for products sold by unit")
    var weightKg: Double

    @Guide(description: "Amount charged for this product: the rightmost value of its line (VL ITEM). Never the unit price, the price per kg or the tax")
    var lineTotal: Double
}

/// Everything read from one photo (one page of the receipt). The totals are read too, as on
/// the test bench, but the app checks the sum against the totals read by OCR, which a model
/// can't invent.
@available(iOS 27.0, *)
@Generable
nonisolated struct GeneratedReceiptPage {
    @Guide(description: "Every purchased product on this page, once each, in printed order", .maximumCount(80))
    var items: [GeneratedReceiptLine]

    @Guide(description: "Sum of the products before tip, service charge or discounts (SUBTOTAL, Total sem gorjeta). On a receipt without a subtotal, the TOTAL. 0 when it is not on this page")
    var printedSubtotal: Double

    @Guide(description: "The receipt's grand total (TOTAL, VALOR A PAGAR) when it is on this page, otherwise 0")
    var printedTotal: Double
}

/// The photo plus its OCR text, sent to the on-device model (iOS 27 image input). Same
/// instructions as the test bench, where this mode was checked on real receipts.
@available(iOS 27.0, *)
nonisolated enum ReceiptPhotoReader {

    /// Rules for Brazilian receipts. The photo and its text go in the prompt, never here.
    static let instructions = """
    You read photos of Brazilian receipts (cupom fiscal, NFC-e) from supermarkets and restaurants.
    List every purchased product exactly once, in printed order.
    A product can take two lines: the line with the item number and the name, then a line shaped like "<quantity>UN X <unit price> <tax>% <line total>" or "<weight>KG X <price per kg> <tax>% <line total>". That second line belongs to the product above it; it is not another product.
    lineTotal is the amount charged for the product (the <line total>), never the unit price, the price per kg or the tax percentage.
    weightKg is only for products whose line shows a weight followed by KG; for every other product it is 0.
    Every name and number you return must be printed on this receipt. The shapes above are not data: never return a value that you can't see on the receipt.
    Brazilian numbers use a comma before the cents and a dot between thousands; return them as plain decimal numbers.
    These are never products: the header, address, CNPJ, CPF, subtotal, total, tip, service charge, discounts, payment method, change (troco), the tax summary and the QR code. Read the subtotal and total only into their own fields.
    Copy names as printed. Never translate them and never invent products. Skip anything unreadable.
    Sometimes the prompt also has text read from the same photo by OCR. Its characters are exact, but its lines can be out of order, split or mixed with other lines. Then copy names and numbers exactly from the OCR text, and use the photo to know which values belong to which product and the quantity of each.
    """

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Reads one page. A price that isn't printed anywhere in the OCR text (OCR reads digits
    /// exactly) was probably misread or invented, so its line gets a warning.
    static func read(_ image: UIImage, ocrText: String) async throws -> [ReceiptScanLine] {
        // The OCR text is the person's data, so it goes in the prompt, never in the instructions.
        var request = "Read every purchased product on this receipt page."
        if !ocrText.isEmpty {
            request += "\n\nOCR text of the same photo:\n\(ocrText.prefix(ReceiptPhotoReading.maxOCRCharacters))"
        }

        // A new session per page keeps every page inside the context window on its own.
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            generating: GeneratedReceiptPage.self,
            // Greedy: the same photo gives the same answer.
            options: GenerationOptions(sampling: .greedy)
        ) {
            request
            Attachment(ReceiptTextReader.upright(image))
        }

        return response.content.items.map { item in
            ReceiptScanLine(
                itemNumber: nil,
                name: item.name,
                quantity: max(item.quantity, 1),
                weightKg: max(item.weightKg, 0),
                total: max(item.lineTotal, 0),
                warning: ReceiptTotals.isPrinted(item.lineTotal, in: ocrText) ? nil : .notOnReceipt
            )
        }
    }
}

#endif
