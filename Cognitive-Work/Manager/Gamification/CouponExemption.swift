//
//  CouponExemption.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// Who is spared which chore because they hold its coupon.
///
/// A coupon bought during cycle X is used by the next division generated after the purchase:
/// - when that division is being generated, X is still the latest cycle
///   (``toApply(coupons:cycles:newCycleKey:)``);
/// - once it is recorded, the coupon is marked as used with the new cycle's key
///   (``consume(_:inCycle:store:)``), so it can be bought again and isn't applied twice.
///
/// The coupon only keeps the division from giving the holder the chore: they may still pick it
/// from the unassigned list if they want to.
enum CouponExemption {

    /// Chore record ID → users that may not get it.
    typealias Map = [CKRecord.ID: Set<CKRecord.ID>]

    /// Coupons the division about to be generated applies: the ones bought in the latest cycle
    /// and not used yet, and, when the division is generated again on the day the latest one was
    /// (same cycle key, `newCycleKey`), the ones the division it replaces had used.
    static func toApply(coupons: [CouponModel], cycles: [HouseCycleModel], newCycleKey: String) -> [CouponModel] {
        guard let latest = HouseCycleModel.latest(cycles) else { return [] }
        return coupons.filter { coupon in
            guard coupon.currentUser != nil else { return false }
            if let consumed = coupon.consumedCycleKey { return consumed == newCycleKey }
            return coupon.purchasedCycleKey == latest.key
        }
    }

    /// Exemptions for the division about to be generated. See ``toApply(coupons:cycles:newCycleKey:)``.
    static func forNextDivision(coupons: [CouponModel], cycles: [HouseCycleModel], newCycleKey: String) -> Map {
        exemptions(from: toApply(coupons: coupons, cycles: cycles, newCycleKey: newCycleKey))
    }

    /// Chore → holders of `coupons`.
    static func exemptions(from coupons: [CouponModel]) -> Map {
        var result: Map = [:]
        for coupon in coupons {
            guard let choreID = coupon.task?.recordID,
                  let holderID = coupon.currentUser?.recordID
            else { continue }
            result[choreID, default: []].insert(holderID)
        }
        return result
    }

    // MARK: - Using

    /// Marks `coupons` as used by the division of the cycle `cycleKey`.
    ///
    /// Each coupon is read again first: one bought again in the meantime (different holder or
    /// cycle) belongs to a new purchase and is left alone. Retries on a conflict with a purchase.
    static func consume(_ coupons: [CouponModel], inCycle cycleKey: String, store: AtomicRecordStore? = nil) async {
        let store = store ?? CloudKitAtomicRecordStore()
        for coupon in coupons {
            guard let id = coupon.recordID else { continue }
            for _ in 0..<3 {
                guard let record = try? await store.fetch([id])[id],
                      var current = CouponModel(record: record),
                      current.currentUser?.recordID == coupon.currentUser?.recordID,
                      current.purchasedCycleKey == coupon.purchasedCycleKey,
                      current.consumedCycleKey != cycleKey
                else { break }

                current.consumedCycleKey = cycleKey
                current.populate(record: record)
                do {
                    try await store.saveAtomically([record])
                    break
                } catch AtomicRecordStoreError.conflict {
                    continue
                } catch {
                    break
                }
            }
        }
    }

    // MARK: - Loading

    /// Coupons and cycles of the house in `zoneID`.
    static func load(houseZoneID zoneID: CKRecordZone.ID) async -> (coupons: [CouponModel], cycles: [HouseCycleModel]) {
        async let coupons = CloudKitManager.shared.fetchAll(CouponModel.self)
        async let cycles = HouseCycleModel.fetchAll(inHouseZone: zoneID)
        let (allCoupons, houseCycles) = await (coupons, cycles)
        return (allCoupons.filter { $0.recordID?.zoneID == zoneID }, houseCycles)
    }
}
