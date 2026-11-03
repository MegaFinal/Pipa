//
//  UnitMeasurement.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//

import Foundation

/// Unit of measurement used to express the amount of a supply item.
///
/// The raw values are stable identifiers safe to persist in CloudKit, while the
/// user-facing text lives in ``abbreviation`` and ``getDisplayName(for:)``.
/// Units are grouped by ``dimension``, and ``convert(_:to:)`` only converts
/// between units sharing the same dimension.
///
/// Example:
/// ```swift
/// let unit = UnitMeasurement.kilogram
/// let label = "\(2) \(unit.abbreviation)"                  // "2 kg"
/// let grams = unit.convert(2, to: .gram)                   // 2000
/// let invalid = unit.convert(2, to: .liter)                // nil
/// ```
enum UnitMeasurement: String, CaseIterable, Identifiable, Codable {
    /// No unit was chosen.
    case undefined
    
    /// Grams, used for small amounts of powder or solid products.
    case gram

    /// Kilograms, used for larger solid products.
    case kilogram

    /// Milliliters, used for small amounts of liquid products.
    case milliliter

    /// Liters, used for larger liquid products.
    case liter

    /// Individual pieces, used for items counted one by one.
    case unit

    /// Packages, used for items bought as a closed bundle.
    case package

    // MARK: - Constants

    /// Conversion factors between units, kept here to avoid magic numbers.
    private enum Conversion {
        static let gramsPerKilogram: Double = 1_000
        static let millilitersPerLiter: Double = 1_000
    }

    // MARK: - Nested Types

    /// The physical quantity a unit measures.
    ///
    /// Conversions are only defined between units of the same dimension.
    enum Dimension: String, CaseIterable, Codable {
        /// No unit was chosen, so nothing can be converted.
        case undefined
        
        /// Units measuring weight, such as grams and kilograms.
        case mass

        /// Units measuring capacity, such as milliliters and liters.
        case volume

        /// Units counting discrete items, such as pieces and packages.
        case count
    }

    // MARK: - Properties

    /// Stable identity used by `ForEach` and `Picker`.
    var id: String { rawValue }

    /// The physical quantity this unit measures.
    var dimension: Dimension {
        switch self {
        case .gram, .kilogram:
            return .mass
        case .milliliter, .liter:
            return .volume
        case .unit, .package:
            return .count
        case .undefined:
            return .undefined
        }
    }

    /// Short label shown next to a value, such as `"500 g"`.
    var abbreviation: String {
        switch self {
        case .gram: return "g"
        case .kilogram: return "kg"
        case .milliliter: return "ml"
        case .liter: return "L"
        case .unit: return "un"
        case .package: return "pct"
        case .undefined: return "indefinido"
        }
    }

    /// How many base units fit in a single unit of this case.
    ///
    /// The base unit is the gram for ``Dimension/mass``, the milliliter for
    /// ``Dimension/volume`` and the piece itself for ``Dimension/count``.
    /// Used as the pivot of ``convert(_:to:)``.
    ///
    /// > Note: ``package`` also reports `1`, since the amount of items inside a
    /// > package varies per product and is not known by this type.
    var baseUnitFactor: Double {
        switch self {
        case .gram, .milliliter, .unit, .package:
            return 1
        case .kilogram:
            return Conversion.gramsPerKilogram
        case .liter:
            return Conversion.millilitersPerLiter
        case .undefined:
            return 0
        }
    }

    // MARK: - Methods

    /// Returns the full unit name, agreeing in number with the given value.
    ///
    /// - Parameter value: Amount of units being described.
    /// - Returns: The singular name when `value` is exactly `1`, the plural otherwise.
    func getDisplayName(for value: Double) -> String {
        let isSingular = value == 1

        switch self {
        case .gram: return isSingular ? L10n.tr("grama") : L10n.tr("gramas")
        case .kilogram: return isSingular ? L10n.tr("quilograma") : L10n.tr("quilogramas")
        case .milliliter: return isSingular ? L10n.tr("mililitro") : L10n.tr("mililitros")
        case .liter: return isSingular ? L10n.tr("litro") : L10n.tr("litros")
        case .unit: return isSingular ? L10n.tr("unidade") : L10n.tr("unidades")
        case .package: return isSingular ? L10n.tr("pacote") : L10n.tr("pacotes")
        case .undefined: return L10n.tr("indefinido")
        }
    }

    /// Converts an amount expressed in this unit into another unit.
    ///
    /// - Parameters:
    ///   - value: Amount expressed in this unit.
    ///   - targetUnit: Unit the amount should be converted to.
    /// - Returns: The converted amount, or `nil` when the units measure
    ///   different dimensions and no conversion is defined.
    func convert(_ value: Double, to targetUnit: UnitMeasurement) -> Double? {
        guard dimension == targetUnit.dimension else {
            return nil
        }

        let valueInBaseUnit = value * baseUnitFactor
        return valueInBaseUnit / targetUnit.baseUnitFactor
    }

    /// Returns every unit that measures the same dimension as this one.
    ///
    /// Useful to populate a picker with only the interchangeable options.
    ///
    /// - Returns: The units sharing this unit's ``dimension``, including itself.
    func getCompatibleUnits() -> [UnitMeasurement] {
        UnitMeasurement.allCases.filter { $0.dimension == dimension }
    }
}
