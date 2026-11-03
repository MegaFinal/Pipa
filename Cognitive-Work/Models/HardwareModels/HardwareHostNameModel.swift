//
//  HardwareModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 02/09/26.
//

import Foundation
import CloudKit

/// The network name (host name) of the house's Harvii device, saved in CloudKit so every
/// member's phone can find it.
///
/// The record type and field are still called "ip" because the device was first reached by IP.
struct HardwareHostNameModel: CloudKitSyncable {
    /// Local identifier. Not saved.
    var id = UUID()
    
    /// The device's network name (for example, `harvii.local`).
    var hostName: String
    
    /// The CloudKit record type.
    static let recordType: String = "HardwareIpModel"
    
    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?
    
    /// Creates the model from a CloudKit record. Returns `nil` when the host name is missing.
    init?(record: CKRecord) {
        guard
            let ip = record["ip"] as? String
        else {
            return nil
        }
        
        self.recordID = record.recordID
        self.hostName = ip
    }
    
    /// Creates a new model, not saved yet.
    init(hostName: String) {
        self.hostName = hostName
    }
    
    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["ip"] = hostName
    }
    
    
    
}
