//
//  RoomBadgeCatalogTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 11/11/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

/// Checks the shape of the room badge catalog (``RoomBadge``).
struct RoomBadgeCatalogTests {

    @Test func everyDefaultRoomHasBadges() {
        for room in DefaultRoomsOnboarding.allCases {
            #expect(!room.badges.isEmpty, "\(room.rawValue) has no badges")
        }
    }

    @Test func roomsHaveTheirOwnNumberOfBadges() {
        #expect(DefaultRoomsOnboarding.kitchen.badges.count == 3)
        #expect(DefaultRoomsOnboarding.powderRoom.badges.count == 2)
        #expect(RoomBadge.allCases.count == 32)
    }

    @Test func badgesOfARoomGetHarderInOrder() {
        for room in DefaultRoomsOnboarding.allCases {
            let thresholds = room.badges.map(\.threshold)
            #expect(thresholds == thresholds.sorted(), "\(room.rawValue) is out of order")
            #expect(Set(thresholds).count == thresholds.count, "\(room.rawValue) repeats a threshold")
            #expect(thresholds.allSatisfy { $0 > 0 })
        }
    }

    @Test func ladderStartsWithTheEasiestBadge() {
        #expect(DefaultRoomsOnboarding.kitchen.badges.first == .torreDeLouca)
        #expect(DefaultRoomsOnboarding.kitchen.badges.last == .chefeMasterDeDelicias)
        #expect(DefaultRoomsOnboarding.powderRoom.badges == [.saboneteDeEnfeite, .aromatizanteDeCheiroDePonei])
    }

    @Test func storedNamesAreUnique() {
        let names = RoomBadge.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        #expect(Set(RoomBadge.allCases.map(\.imageName)).count == names.count)
    }
}
