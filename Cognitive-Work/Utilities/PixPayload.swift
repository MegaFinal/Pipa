//
//  PixPayload.swift
//  Cognitive-Work
//

import Foundation

/// Builds the Pix "copia e cola" (static BR Code) and cleans up Pix keys. Pure, so it can be
/// tested without CloudKit or UI.
enum PixPayload {

    /// Largest key the BR Code allows in its merchant account field.
    static let maxKeyLength = 77

    // MARK: - Keys

    /// The key as Pix expects it, or `nil` when it isn't a valid CPF, CNPJ, phone, e-mail or
    /// random key.
    ///
    /// - Phones need the `+55` prefix: without it, 11 digits are read as a CPF.
    /// - CPF and CNPJ lose their dots, dashes and slashes.
    static func normalizedKey(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.contains("@") {
            let email = text.lowercased()
            let parts = email.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !email.contains(" ") else { return nil }
            return email.count <= maxKeyLength ? email : nil
        }

        if UUID(uuidString: text) != nil {
            return text.lowercased()
        }

        let digits = text.filter(\.isNumber)

        if text.hasPrefix("+") {
            // +55 + DDD (2) + number (8 or 9)
            return digits.hasPrefix("55") && (12...13).contains(digits.count) ? "+" + digits : nil
        }

        return digits.count == 11 || digits.count == 14 ? digits : nil
    }

    // MARK: - Payload

    /// The "copia e cola" text for `amount` reais sent to `key`.
    ///
    /// - Parameters:
    ///   - key: A key already cleaned by ``normalizedKey(_:)``.
    ///   - amount: Value in reais; omitted from the code when zero or negative.
    ///   - receiverName: Shown by the bank app. Accents are removed and it is cut to 25 characters.
    ///   - city: Required by the format. Cut to 15 characters.
    static func copyAndPaste(key: String, amount: Double, receiverName: String, city: String = "BRASIL") -> String {
        let account = field("00", "br.gov.bcb.pix") + field("01", key)

        var payload = ""
        payload += field("00", "01")
        payload += field("26", account)
        payload += field("52", "0000")
        payload += field("53", "986")
        if amount > 0 {
            payload += field("54", String(format: "%.2f", amount))
        }
        payload += field("58", "BR")
        payload += field("59", sanitized(receiverName, fallback: "PIPA", limit: 25))
        payload += field("60", sanitized(city, fallback: "BRASIL", limit: 15))
        payload += field("62", field("05", "***"))

        payload += "6304"
        return payload + crc16(payload)
    }

    // MARK: - Internals

    /// One field of the Pix code: its ID, the value's length (two digits) and the value.
    private static func field(_ id: String, _ value: String) -> String {
        id + String(format: "%02d", value.count) + value
    }

    /// ASCII letters, digits and spaces only, as bank apps expect.
    private static func sanitized(_ text: String, fallback: String, limit: Int) -> String {
        let folded = text.applyingTransform(.stripDiacritics, reverse: false) ?? text
        let cleaned = String(folded.unicodeScalars.filter {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == " ")
        }).trimmingCharacters(in: .whitespaces)

        let result = String(cleaned.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? fallback : result
    }

    /// CRC16/CCITT-FALSE (polynomial 0x1021, start 0xFFFF), as 4 uppercase hex digits.
    private static func crc16(_ text: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in text.utf8 {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return String(format: "%04X", crc)
    }
}
