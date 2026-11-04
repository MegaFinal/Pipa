//
//  HardwareHostNameModelTests.swift
//  Cognitive-WorkTests
//
//  Created by Isabela Hissa Pinto on 03/11/26.
//

import Testing
import CloudKit
@testable import Cognitive_Work

/// Checks how the Harvii host name and Wi-Fi name go into and come out of a CloudKit record.
/// Only builds records in memory: nothing is sent to CloudKit.
struct HardwareHostNameModelTests {

    private func emptyRecord() -> CKRecord {
        CKRecord(recordType: HardwareHostNameModel.recordType)
    }

    @Test func savesAndReadsHostAndWifiName() throws {
        let record = emptyRecord()
        HardwareHostNameModel(hostName: "harvi-ab12.local", wifiName: "Casa da Bela").populate(record: record)

        let model = try #require(HardwareHostNameModel(record: record))
        #expect(model.hostName == "harvi-ab12.local")
        #expect(model.wifiName == "Casa da Bela")
        #expect(model.recordID == record.recordID)
    }

    @Test func keepsTheOldFieldNameForTheHost() {
        let record = emptyRecord()
        HardwareHostNameModel(hostName: "harvi-ab12.local").populate(record: record)

        // The record type and field are still called "ip" (see the model's doc).
        #expect(record["ip"] as? String == "harvi-ab12.local")
    }

    @Test func readsOldRecordsWithoutWifiName() throws {
        let record = emptyRecord()
        record["ip"] = "harvi-ab12.local"

        let model = try #require(HardwareHostNameModel(record: record))
        #expect(model.hostName == "harvi-ab12.local")
        #expect(model.wifiName == nil)
    }

    @Test func leavesWifiNameEmptyWhenNotKnown() {
        let record = emptyRecord()
        HardwareHostNameModel(hostName: "harvi-ab12.local", wifiName: nil).populate(record: record)

        #expect(record["wifiName"] == nil)
    }

    @Test func rejectsRecordsWithoutHost() {
        let record = emptyRecord()
        record["wifiName"] = "Casa da Bela"

        #expect(HardwareHostNameModel(record: record) == nil)
    }
}
