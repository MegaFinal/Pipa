//
//  CloudKitSyncable.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import CloudKit
import Foundation

/// A type that can be persisted as a CloudKit record.
///
/// Conforming types describe how their properties map to and from a
/// `CKRecord`. Once a model conforms, `CloudKitManager`'s generic CRUD
protocol CloudKitSyncable {

    /// The CloudKit record type name (e.g. "House", "User", "ChoreModel").
    static var recordType: String { get }

    /// The fields list queries should transfer, or `nil` to transfer every field.
    ///
    /// > Important: every field ``init(record:)`` requires must appear in this list, otherwise
    /// > decoding silently fails and the query looks empty. Leaving it `nil` — the default —
    /// > keeps the previous whole-record behaviour.
    static var listDesiredKeys: [CKRecord.FieldKey]? { get }

    /// The underlying CloudKit record identifier.
    var recordID: CKRecord.ID? { get set }

    /// Writes this model's fields into `record`.
    func populate(record: CKRecord)

    /// Builds a model instance from a fetched record.
    init?(record: CKRecord)
}

extension CloudKitSyncable {

    /// Transfers every field, preserving the behaviour models had before
    /// ``listDesiredKeys`` existed.
    static var listDesiredKeys: [CKRecord.FieldKey]? { nil }
}
