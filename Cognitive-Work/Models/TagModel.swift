//
//  TagModel.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//

import Foundation
import CloudKit
import SwiftUI
/// A colored label that can be attached to shopping list items.
///
/// > Note: Not fully implemented yet (see the TODO below).
struct TagModel: CloudKitSyncable {
    //TODO: implement the class diagram
    /// The CloudKit record type.
    static var recordType: String = "TagModel"
    
    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?
    
    /// The tag's text.
    var name: String
    /// The tag's color (saved as a hex string).
    var color: Color
    
    /// Creates the model from a CloudKit record. Returns `nil` when the name or color is missing.
    init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let colorHex = record["color"] as? String
        else {
            return nil
        }
        
        self.name = name
        self.color = Color(hex: colorHex) ?? .gray
    }
    
    /// Creates a new tag, not saved yet.
    init(name: String, color: Color) {
        self.name = name
        self.color = color
    }
    
    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["name"] = name
        record["color"] = color.toHex()
    }
}

