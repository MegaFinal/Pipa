//
//  ReceiptTextReader.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

@preconcurrency import Vision
import UIKit

/// Reads the text of a receipt photo with Vision, keeping its layout: words on the same printed
/// row are joined into one line, and spaces keep them roughly in their columns ("ITEM | DESC |
/// QTD | VL.UNIT | VL.ITEM"), which ``ReceiptParser`` relies on.
///
/// `nonisolated`: Vision calls back on a background thread, and the app isolates code to the
/// main actor by default.
nonisolated enum ReceiptTextReader {

    /// One recognized piece of text and where it is (Vision's normalized coordinates, y up).
    private struct Token {
        let text: String
        let box: CGRect
    }

    /// The photo's text, one printed row per line. Empty when nothing was read.
    static func text(from image: UIImage) async -> String {
        guard let cgImage = upright(image).cgImage else { return "" }

        let rows: [[Token]] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: error == nil ? groupIntoRows(observations) : [])
            }
            request.recognitionLevel = .accurate
            // Portuguese receipts; English for brand names.
            request.recognitionLanguages = ["pt-BR", "en-US"]
            // Language correction "fixes" codes and abbreviations into wrong words; the parser
            // copes with raw OCR better.
            request.usesLanguageCorrection = false
            // Thermal receipts have small print.
            request.minimumTextHeight = 0.008

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
        return rows.map(render).joined(separator: "\n")
    }

    // MARK: - Rows

    /// Groups the pieces of text that sit at the same height, top to bottom, each row left to
    /// right. Vision may return "001 0789… SACOLA" and "1,70" separately even on the same row.
    private static func groupIntoRows(_ observations: [VNRecognizedTextObservation]) -> [[Token]] {
        let tokens = observations.compactMap { observation -> Token? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Token(text: text, box: observation.boundingBox)
        }
        guard !tokens.isEmpty else { return [] }

        // Adaptive: small print photographed from afar has thin rows, close-ups thick ones.
        let averageHeight = tokens.map(\.box.height).reduce(0, +) / CGFloat(tokens.count)
        let tolerance = max(0.008, min(0.025, averageHeight * 0.75))

        var rows: [[Token]] = []
        for token in tokens.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.box.midY - token.box.midY) < tolerance
            }) {
                rows[index].append(token)
            } else {
                rows.append([token])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// One row as text, with spaces that put each piece near its column (100 columns wide).
    private static func render(_ row: [Token]) -> String {
        let width = 100
        var line = ""
        for token in row {
            let column = min(width - 1, Int(max(0, min(1, token.box.minX)) * CGFloat(width)))
            if column > line.count {
                line += String(repeating: " ", count: column - line.count)
            } else if !line.isEmpty {
                line += " "
            }
            line += token.text
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Image

    /// The photo with its pixels upright: Vision reads `cgImage`, which ignores the orientation
    /// a camera photo is tagged with.
    private static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
