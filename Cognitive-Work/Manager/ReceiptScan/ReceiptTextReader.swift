//
//  ReceiptTextReader.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation
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

    /// How the text is laid out.
    enum Style {
        /// Raw OCR in columns, for ``ReceiptParser``.
        case layout
        /// Language correction on and words joined by single spaces: the text the photo
        /// reading sends to the model with the photo (``ReceiptPhotoReader``), as on the test
        /// bench where that mode was checked.
        case plain
    }

    /// The photo's text, one printed row per line. Empty when nothing was read.
    static func text(from image: UIImage, style: Style = .layout) async -> String {
        guard let cgImage = upright(image).cgImage else { return "" }

        let rows: [[Token]] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: error == nil ? groupIntoRows(observations, style: style) : [])
            }
            request.recognitionLevel = .accurate
            // Portuguese receipts; English for brand names.
            request.recognitionLanguages = ["pt-BR", "en-US"]
            // Language correction "fixes" codes and abbreviations into wrong words; the parser
            // copes with raw OCR better. The model, which also sees the photo, reads the
            // corrected text better.
            request.usesLanguageCorrection = style == .plain
            // Thermal receipts have small print.
            request.minimumTextHeight = style == .layout ? 0.008 : 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
        switch style {
        case .layout: return rows.map(render).joined(separator: "\n")
        case .plain: return rows.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        }
    }

    // MARK: - Rows

    /// Groups the pieces of text that sit at the same height, top to bottom, each row left to
    /// right. Vision may return "001 0789… SACOLA" and "1,70" separately even on the same row.
    private static func groupIntoRows(_ observations: [VNRecognizedTextObservation], style: Style) -> [[Token]] {
        let tokens = observations.compactMap { observation -> Token? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Token(text: text, box: observation.boundingBox)
        }
        guard !tokens.isEmpty else { return [] }

        // Adaptive: small print photographed from afar has thin rows, close-ups thick ones.
        let averageHeight = tokens.map(\.box.height).reduce(0, +) / CGFloat(tokens.count)
        let tolerance = style == .layout ? max(0.008, min(0.025, averageHeight * 0.75)) : 0.015

        // Each piece joins the closest row (by its average height) that has nothing in the same
        // columns: on a tilted photo two printed rows can be closer than the tolerance, but two
        // pieces side by side never overlap ("01 0789… LTE" and "02 0789… LTE" both start at the
        // left edge, so they're two rows).
        var rows: [[Token]] = []
        for token in tokens.sorted(by: { $0.box.midY > $1.box.midY }) {
            let candidates = rows.indices.compactMap { index -> (index: Int, distance: CGFloat)? in
                let row = rows[index]
                let midY = row.map(\.box.midY).reduce(0, +) / CGFloat(row.count)
                let distance = abs(midY - token.box.midY)
                guard distance < tolerance, !row.contains(where: { overlaps($0.box, token.box) }) else { return nil }
                return (index, distance)
            }
            if let closest = candidates.min(by: { $0.distance < $1.distance }) {
                rows[closest.index].append(token)
            } else {
                rows.append([token])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// Whether two pieces share columns: more than a third of the narrower one. Vision's boxes
    /// of neighbors on the same row may touch, but not cover each other.
    private static func overlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let shared = min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX)
        return shared > min(lhs.width, rhs.width) / 3
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
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
