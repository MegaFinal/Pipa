//
//  Untitled.swift
//  ColorHexExtension
//
//  Created by Jonas Fernando Nascimento Melo on 28/08/26.
//

import SwiftUI

extension Color {

    /// Cria uma cor a partir de uma string hexadecimal.
    ///
    /// Aceita `#` opcional e os formatos `RGB`, `RRGGBB` e `RRGGBBAA`.
    /// Retorna `nil` quando a string tem tamanho inválido ou caracteres não-hex.
    ///
    /// ```swift
    /// Color(hex: "#FF9500")     // laranja
    /// Color(hex: "f90")         // mesmo laranja, forma curta
    /// Color(hex: "FF950080")    // laranja com 50% de opacidade
    /// ```
    init?(hex: String) {
        // Remove `#`, espaços e normaliza para maiúsculas.
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        // Rejeita qualquer caractere fora de 0-9 / A-F antes de converter.
        guard !cleaned.isEmpty,
              cleaned.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }

        let r, g, b, a: Double

        switch cleaned.count {
        case 3:
            // RGB: cada dígito representa um par (F -> FF), daí o `* 17`.
            r = Double((value >> 8) & 0xF) * 17 / 255
            g = Double((value >> 4) & 0xF) * 17 / 255
            b = Double(value & 0xF) * 17 / 255
            a = 1

        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1

        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255

        default:
            return nil
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Cria uma cor a partir de um literal hexadecimal, sem opcional.
    ///
    /// Útil para constantes do design system, onde o valor é conhecido
    /// em tempo de compilação e não faz sentido desembrulhar:
    ///
    /// ```swift
    /// static let brand = Color(hex: 0xFF9500)
    /// ```
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Devolve a representação hexadecimal da cor.
    ///
    /// - Parameter includeAlpha: quando `true`, gera `#RRGGBBAA`.
    /// - Returns: `nil` para cores que não resolvem em componentes RGB
    ///   (gradientes, materiais e algumas cores dinâmicas do sistema).
    func toHex(includeAlpha: Bool = false) -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }

        // Clampa antes de converter: sRGB estendido permite valores fora de 0...1.
        let r = Int((min(max(components[0], 0), 1) * 255).rounded())
        let g = Int((min(max(components[1], 0), 1) * 255).rounded())
        let b = Int((min(max(components[2], 0), 1) * 255).rounded())

        guard includeAlpha else {
            return String(format: "#%02X%02X%02X", r, g, b)
        }

        let alpha = components.count >= 4 ? components[3] : 1
        let a = Int((min(max(alpha, 0), 1) * 255).rounded())

        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

extension Color {
    /// Background of the profile screens and sheets (the iOS grouped gray, `#F2F2F7`).
    static let groupedBackground = Color(hex: 0xF2F2F7)
}
