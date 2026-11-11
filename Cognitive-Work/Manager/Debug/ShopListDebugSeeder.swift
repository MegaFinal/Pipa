//
//  ShopListDebugSeeder.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 10/11/26.
//

#if DEBUG
import Foundation
import CloudKit

/// DEBUG only: fills the house's shopping list with sample items (4 or 5 per category, each with
/// a price and a fitting unit), split among the house's real housemates.
///
/// Every item it creates is remembered on this device, so ``removeSeededData()`` deletes
/// exactly those and never something the house added for real.
@MainActor
enum ShopListDebugSeeder {

    /// Why seeding failed.
    enum SeedError: LocalizedError {
        /// The signed-in user has no house.
        case noHouse
        /// The house has no shopping list yet.
        case noShopList
        /// No housemate was found to split the items with.
        case noHousemates
        /// CloudKit rejected the save (the message comes from ``CloudKitManager/errorMessage``).
        case saveFailed(String?)

        var errorDescription: String? {
            switch self {
            case .noHouse: return "Nenhuma casa encontrada."
            case .noShopList: return "A casa ainda não tem lista de compras."
            case .noHousemates: return "Nenhum morador encontrado na casa."
            case .saveFailed(let message): return message ?? "O CloudKit recusou o salvamento."
            }
        }
    }

    /// What one seeding created.
    struct Result {
        let housemates: [String]
        let itemCount: Int
    }

    // MARK: - Sample data

    /// One sample product: what the item gets when it is created.
    private struct SampleItem {
        let name: String
        let quantity: Int
        let unit: UnitMeasurement
        let totalPrice: Double
    }

    /// Sample products of every category, with typical prices (in reais) for the whole quantity.
    private static let catalog: [ShopItemCategory: [SampleItem]] = [
        .food: [
            SampleItem(name: "Rice", quantity: 5, unit: .kilogram, totalPrice: 32.90),
            SampleItem(name: "Beans", quantity: 1, unit: .kilogram, totalPrice: 8.49),
            SampleItem(name: "Spaghetti", quantity: 3, unit: .package, totalPrice: 14.97),
            SampleItem(name: "Coffee", quantity: 500, unit: .gram, totalPrice: 21.90),
            SampleItem(name: "Eggs", quantity: 12, unit: .unit, totalPrice: 13.90)
        ],
        .produce: [
            SampleItem(name: "Bananas", quantity: 1, unit: .kilogram, totalPrice: 6.99),
            SampleItem(name: "Tomatoes", quantity: 1, unit: .kilogram, totalPrice: 8.90),
            SampleItem(name: "Potatoes", quantity: 2, unit: .kilogram, totalPrice: 11.80),
            SampleItem(name: "Lettuce", quantity: 1, unit: .unit, totalPrice: 3.49),
            SampleItem(name: "Apples", quantity: 1, unit: .kilogram, totalPrice: 10.90)
        ],
        .drinks: [
            SampleItem(name: "Whole milk", quantity: 6, unit: .liter, totalPrice: 33.54),
            SampleItem(name: "Orange juice", quantity: 1, unit: .liter, totalPrice: 12.90),
            SampleItem(name: "Soda", quantity: 2, unit: .liter, totalPrice: 9.99),
            SampleItem(name: "Bottled water", quantity: 1, unit: .package, totalPrice: 14.90),
            SampleItem(name: "Beer", quantity: 12, unit: .unit, totalPrice: 47.88)
        ],
        .cleaning: [
            SampleItem(name: "Dish soap", quantity: 3, unit: .unit, totalPrice: 7.47),
            SampleItem(name: "Bleach", quantity: 2, unit: .liter, totalPrice: 9.98),
            SampleItem(name: "Laundry detergent", quantity: 1, unit: .package, totalPrice: 24.90),
            SampleItem(name: "Fabric softener", quantity: 2, unit: .liter, totalPrice: 18.90),
            SampleItem(name: "Sponges", quantity: 4, unit: .unit, totalPrice: 6.99)
        ],
        .hygiene: [
            SampleItem(name: "Toilet paper", quantity: 1, unit: .package, totalPrice: 22.90),
            SampleItem(name: "Toothpaste", quantity: 2, unit: .unit, totalPrice: 11.98),
            SampleItem(name: "Bar soap", quantity: 4, unit: .unit, totalPrice: 9.96),
            SampleItem(name: "Shampoo", quantity: 400, unit: .milliliter, totalPrice: 19.90),
            SampleItem(name: "Deodorant", quantity: 2, unit: .unit, totalPrice: 25.80)
        ],
        .home: [
            SampleItem(name: "LED light bulb", quantity: 2, unit: .unit, totalPrice: 19.98),
            SampleItem(name: "AA batteries", quantity: 4, unit: .unit, totalPrice: 16.90),
            SampleItem(name: "Trash bags", quantity: 1, unit: .package, totalPrice: 12.90),
            SampleItem(name: "Paper towels", quantity: 2, unit: .unit, totalPrice: 9.98),
            SampleItem(name: "Coffee filters", quantity: 1, unit: .package, totalPrice: 5.49)
        ],
        .pets: [
            SampleItem(name: "Dog food", quantity: 3, unit: .kilogram, totalPrice: 54.90),
            SampleItem(name: "Cat litter", quantity: 4, unit: .kilogram, totalPrice: 21.90),
            SampleItem(name: "Wet cat food", quantity: 6, unit: .unit, totalPrice: 17.94),
            SampleItem(name: "Pet treats", quantity: 1, unit: .package, totalPrice: 12.90)
        ],
        .other: [
            SampleItem(name: "Charcoal", quantity: 1, unit: .package, totalPrice: 24.90),
            SampleItem(name: "Tape", quantity: 1, unit: .unit, totalPrice: 6.50),
            SampleItem(name: "Ice", quantity: 2, unit: .package, totalPrice: 13.98),
            SampleItem(name: "Candles", quantity: 1, unit: .package, totalPrice: 8.90),
            SampleItem(name: "Paper cups", quantity: 1, unit: .package, totalPrice: 7.90)
        ]
    ]

    // MARK: - Seeding

    /// Adds 4 or 5 pending items of every category to the house's shopping list. Each item is
    /// for a random group of the house's housemates and was added by one of them.
    ///
    /// - Returns: The names of the housemates used and how many items were created.
    @discardableResult
    static func seed() async throws -> Result {
        let cloud = CloudKitManager.shared

        guard let house = try? await cloud.currentHouse(), house.recordID != nil else {
            throw SeedError.noHouse
        }
        guard let list = await house.shopList, let listID = list.recordID else {
            throw SeedError.noShopList
        }

        // MARK: Housemates
        let members = cloud.deduplicatedByOwner(await cloud.fetchHouseUserRecords())
        let housemates = members.compactMap(\.recordID).map { CKRecord.Reference(recordID: $0, action: .none) }
        guard !housemates.isEmpty else { throw SeedError.noHousemates }

        // MARK: Items
        let listReference = CKRecord.Reference(recordID: listID, action: .none)

        var itemRecords: [CKRecord] = []
        for category in ShopItemCategory.listOrder {
            let samples = (catalog[category] ?? []).shuffled()
            for sample in samples.prefix(Int.random(in: 4...5)) {
                let item = ShopListItem(
                    name: sample.name,
                    totalPrice: sample.totalPrice,
                    quantity: sample.quantity,
                    unitMeasurement: sample.unit,
                    category: category,
                    relatedUsers: randomGroup(of: housemates),
                    addedByUser: housemates.randomElement()
                )
                let record = CKRecord(
                    recordType: ShopListItem.recordType,
                    recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: listID.zoneID)
                )
                item.populate(record: record)
                record.parent = listReference
                itemRecords.append(record)
            }
        }

        guard await cloud.batchSave(records: itemRecords, zoneID: listID.zoneID) else {
            throw SeedError.saveFailed(cloud.errorMessage)
        }
        remember(itemRecords.map(\.recordID))

        return Result(housemates: members.map(\.name), itemCount: itemRecords.count)
    }

    /// A random, non-empty group of `people`.
    private static func randomGroup(of people: [CKRecord.Reference]) -> [CKRecord.Reference] {
        guard !people.isEmpty else { return [] }
        return Array(people.shuffled().prefix(Int.random(in: 1...people.count)))
    }

    // MARK: - Cleanup

    /// Whether this device seeded records that were not removed yet.
    static var hasSeededData: Bool { !seededRecordIDs.isEmpty }

    /// Deletes every item created by ``seed()`` on this device.
    ///
    /// - Returns: `false` when CloudKit rejects a delete (what was not deleted stays remembered).
    @discardableResult
    static func removeSeededData() async -> Bool {
        let byZone = Dictionary(grouping: seededRecordIDs, by: \.zoneID)
        var remaining: [CKRecord.ID] = []
        for (zoneID, ids) in byZone {
            if await !CloudKitManager.shared.delete(recordIDs: ids, zoneID: zoneID) {
                remaining += ids
            }
        }
        seededRecordIDs = remaining
        return remaining.isEmpty
    }

    // MARK: - Storage

    /// Where the seeded record IDs are kept between launches.
    private static let storageKey = "debug.shopListSeeder.recordIDs"

    /// Every record created by the seeder and not removed yet.
    private static var seededRecordIDs: [CKRecord.ID] {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
            return (try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: CKRecord.ID.self, from: data)) ?? []
        }
        set {
            let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Adds `ids` to ``seededRecordIDs``.
    private static func remember(_ ids: [CKRecord.ID]) {
        seededRecordIDs += ids
    }
}
#endif
