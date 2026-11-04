//
//  CalendarManager.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/09/26.
//

import Foundation
import EventKit
import CloudKit

/// Keeps the user's chores in sync with a "Pipa" calendar in the Apple Calendar app.
///
/// Only chores the signed-in member is responsible for and hasn't done yet become events.
@Observable
class CalendarManager {
    /// Global shared singleton instance
    static let shared = CalendarManager()
    
    /// Underlying system calendar event store
    private let store = EKEventStore()
    /// Dedicated calendar name used by the application
    private let calendarTitle = "Pipa"
    
    /// Use ``shared``.
    private init() {}
    
    /// Requests full access to the user's event calendar.
    ///
    /// - Returns: A Boolean value indicating whether access was granted.
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted
        } catch {
            return false
        }
    }
    
    /// Finds the dedicated "Pipa" calendar, or creates one automatically if it does not exist.
    private func dedicatedCalendar() throws -> EKCalendar {
        let calendars = store.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == calendarTitle }) {
            return existing
        }
        
        let newCal = EKCalendar(for: .event, eventStore: store)
        newCal.title = calendarTitle
        
        // Match a suitable account source for the new calendar
        if let iCloudSource = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.contains("iCloud") }) {
            newCal.source = iCloudSource
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            newCal.source = localSource
        } else if let defaultSource = store.defaultCalendarForNewEvents?.source {
            newCal.source = defaultSource
        } else if let firstSource = store.sources.first {
            newCal.source = firstSource
        }
        
        try store.saveCalendar(newCal, commit: true)
        return newCal
    }
    
    /// Commits all buffered batch calendar changes.
    func commitBatch() throws {
        try store.commit()
    }
     
    // MARK: - Helper Lookup & Robust Finding
    
    /// Finds an existing calendar item by its unique identifier.
    private func findExistingEvent(identifier: String?) -> EKEvent? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let item = store.calendarItem(withIdentifier: identifier)
        return item as? EKEvent
    }

    /// Finds or creates a calendar event for a recurrent assignment.
    private func findOrCreateRecurrentEvent(for assignment: RecurrentAssignmentModel, choreName: String, calendar: EKCalendar) throws -> EKEvent {
        // Try to find the event using the saved identifier first
        if let identifier = assignment.calendarEventIdentifier,
           let event = findExistingEvent(identifier: identifier) {
            return event
        }
          
        // Fallback strategy: Match by day and title if the ID has become invalid
        let startOfDay = Calendar.current.startOfDay(for: assignment.day)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
          
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: [calendar])
        let events = store.events(matching: predicate)
          
        // Reuse matching event and self-heal its identifier
        if let matchedEvent = events.first(where: { $0.title == choreName || $0.title == choreName.localizedDefault }),
           let matchedID = matchedEvent.eventIdentifier {
            assignment.calendarEventIdentifier = matchedID
            return matchedEvent
        }
          
        return EKEvent(eventStore: store)
    }

    /// Finds or creates a calendar event for a one-off chore.
    private func findOrCreateOneOffEvent(for chore: ChoreModel, calendar: EKCalendar) throws -> EKEvent {
        // Try to find using the existing ID
        if let event = findExistingEvent(identifier: chore.calendarEventIdentifier) {
            return event
        }
          
        // Fallback strategy using due date and title
        if let dueDate = chore.dueDate {
            let startOfDay = Calendar.current.startOfDay(for: dueDate)
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
              
            let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: [calendar])
            let events = store.events(matching: predicate)
              
            if let matchedEvent = events.first(where: { $0.title == chore.name || $0.title == chore.localizedName }) {
                if let matchedID = matchedEvent.eventIdentifier {
                    chore.calendarEventIdentifier = matchedID
                }
                return matchedEvent
            }
        }
          
        return EKEvent(eventStore: store)
    }
      
    // MARK: - Event Construction & Staging (For Batch Sync)
     
    /// Creates or updates the calendar event of a one-off chore, without committing it yet.
    ///
    /// Nothing happens unless the chore is one-off, has a due date, isn't done and belongs to
    /// `currentUserID`. Call the store's commit after staging every event (batch sync).
    /// - Returns: `true` when the chore got a new event ID (so it must be saved).
    @discardableResult
    func upsertOneOffEventWithoutPersisting(for chore: ChoreModel, currentUserID: CKRecord.ID) throws -> Bool {
        // Check conditions: one-off chore, current user is responsible, has due date, and not completed
        guard chore.frequency == .none,
              let responsibleRef = chore.currentResponsibleReference,
              responsibleRef.recordID == currentUserID,
              let dueDate = chore.dueDate,
              !chore.isDone else {
            // Remove event if conditions are no longer met
            if let identifier = chore.calendarEventIdentifier {
                removeEvent(identifier: identifier, title: chore.name, date: chore.dueDate)
                chore.calendarEventIdentifier = nil
                return true
            }
            return false
        }
          
        let calendar = try dedicatedCalendar()
        let event = try findOrCreateOneOffEvent(for: chore, calendar: calendar)
          
        // Populate event details
        event.title = chore.localizedName
        event.notes = eventNotes(for: chore, separator: "\n\n")
          
        event.isAllDay = true
        event.startDate = dueDate
        event.endDate = dueDate
        event.calendar = calendar
          
        // Stage changes without committing immediately
        try store.save(event, span: .thisEvent, commit: false)
          
        let newIdentifier = event.eventIdentifier
        if chore.calendarEventIdentifier != newIdentifier, let newIdentifier {
            chore.calendarEventIdentifier = newIdentifier
            return true
        }
        return false
    }
      
    /// Creates, updates or removes the calendar event of one occurrence of a recurring chore,
    /// without committing it yet.
    ///
    /// The event is removed when the occurrence is done or belongs to someone else.
    /// - Returns: `true` when the occurrence's event ID changed (so it must be saved).
    @discardableResult
    func upsertRecurrentEventWithoutPersisting(for assignment: RecurrentAssignmentModel, chore: ChoreModel, currentUserID: CKRecord.ID) throws -> Bool {
        let isAssignedToMe = (assignment.userReferences ?? []).contains { $0.recordID == currentUserID }
        let isNotCompleted = !assignment.isCompleted
          
        // Must belong to the current user and remain uncompleted
        guard isAssignedToMe, isNotCompleted else {
            if let identifier = assignment.calendarEventIdentifier {
                removeEvent(identifier: identifier, title: chore.name, date: assignment.day)
                assignment.calendarEventIdentifier = nil
                return true
            }
            return false
        }
          
        let calendar = try dedicatedCalendar()
        let event = try findOrCreateRecurrentEvent(for: assignment, choreName: chore.name, calendar: calendar)
          
        // Populate event details
        event.title = chore.localizedName
        event.notes = eventNotes(for: chore, separator: "\n")
          
        event.isAllDay = true
        event.startDate = assignment.day
        event.endDate = assignment.day
        event.calendar = calendar
          
        try store.save(event, span: .thisEvent, commit: false)
          
        let newIdentifier = event.eventIdentifier
        if assignment.calendarEventIdentifier != newIdentifier, let newIdentifier {
            assignment.calendarEventIdentifier = newIdentifier
            return true
        }
        return false
    }
      
    // MARK: - Public APIs: Batch Synchronization & Deletion
      
    /// Batch synchronizes all chores and assignments to the calendar.
    func batchSyncAllChores(
        _ assignments: [RecurrentAssignmentModel],
        allChores: [ChoreModel],
        choresMap: [CKRecord.ID: ChoreModel],
        currentUserID: CKRecord.ID
    ) async {
        guard await requestAccess() else { return }
          
        var assignmentsToPersist: [RecurrentAssignmentModel] = []
        var choresToPersist: [ChoreModel] = []
          
        do {
            // Process recurring tasks
            for assignment in assignments {
                guard let choreRef = assignment.choreReference?.recordID,
                      let chore = choresMap[choreRef] else { continue }
                 
                let changed = try upsertRecurrentEventWithoutPersisting(for: assignment, chore: chore, currentUserID: currentUserID)
                if changed {
                    assignmentsToPersist.append(assignment)
                }
            }
              
            // Process one-off tasks
            for chore in allChores {
                let originalID = chore.calendarEventIdentifier
                let changed = try upsertOneOffEventWithoutPersisting(for: chore, currentUserID: currentUserID)
                if originalID != chore.calendarEventIdentifier || changed {
                    choresToPersist.append(chore)
                }
            }
              
            // Commit database transaction
            try commitBatch()
              
            // Write back identifiers to CloudKit asynchronously
            if !assignmentsToPersist.isEmpty {
                await CloudKitManager.shared.batchUpdate(assignmentsToPersist)
            }
            if !choresToPersist.isEmpty {
                await CloudKitManager.shared.batchUpdate(choresToPersist)
            }
        } catch {
            // Handle error silently
        }
    }
      
    /// Clears all events inside the dedicated calendar.
    func clearAllMyCalendarEvents() async {
        guard await requestAccess() else { return }
        do {
            let calendarObj = try dedicatedCalendar()
            let startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
            let endDate = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
              
            let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendarObj])
            let events = store.events(matching: predicate)
              
            for event in events {
                try store.remove(event, span: .thisEvent, commit: false)
            }
            try store.commit()
        } catch {
            // Handle error silently
        }
    }
      
    // MARK: - Single Item Operations
      
    /// Creates or updates a single one-off chore calendar event.
    func upsertOneOffEvent(for chore: ChoreModel, currentUserID: CKRecord.ID) async throws {
        guard await requestAccess() else { return }

        guard chore.frequency == .none,
              let responsibleRef = chore.currentResponsibleReference,
              responsibleRef.recordID == currentUserID,
              let dueDate = chore.dueDate,
              !chore.isDone else {
            removeEvent(identifier: chore.calendarEventIdentifier, title: chore.name, date: chore.dueDate)
            chore.calendarEventIdentifier = nil
            await CloudKitManager.shared.update(chore)
            return
        }
          
        let calendar = try dedicatedCalendar()
        let event = try findOrCreateOneOffEvent(for: chore, calendar: calendar)
          
        event.title = chore.localizedName
        event.notes = eventNotes(for: chore, separator: "\n\n")
          
        event.isAllDay = true
        event.startDate = dueDate
        event.endDate = dueDate
        event.calendar = calendar
          
        try store.save(event, span: .thisEvent, commit: true)
          
        let newIdentifier = event.eventIdentifier
        if chore.calendarEventIdentifier != newIdentifier, let newIdentifier {
            chore.calendarEventIdentifier = newIdentifier
            await CloudKitManager.shared.update(chore)
        }
    }
      
    /// Creates or updates a single recurrent assignment calendar event.
    func upsertRecurrentEvent(for assignment: RecurrentAssignmentModel, chore: ChoreModel, currentUserID: CKRecord.ID) async throws {
        guard await requestAccess() else { return }

        let isAssignedToMe = (assignment.userReferences ?? []).contains { $0.recordID == currentUserID }
        let isNotCompleted = !assignment.isCompleted
          
        guard isAssignedToMe, isNotCompleted else {
            removeEvent(identifier: assignment.calendarEventIdentifier, title: chore.name, date: assignment.day)
            assignment.calendarEventIdentifier = nil
            await CloudKitManager.shared.update(assignment)
            return
        }
          
        let calendar = try dedicatedCalendar()
        let event = try findOrCreateRecurrentEvent(for: assignment, choreName: chore.name, calendar: calendar)
          
        event.title = chore.localizedName
        event.notes = eventNotes(for: chore, separator: "\n")
          
        event.isAllDay = true
        event.startDate = assignment.day
        event.endDate = assignment.day
        event.calendar = calendar
          
        try store.save(event, span: .thisEvent, commit: true)
          
        let newIdentifier = event.eventIdentifier
        if let newIdentifier, assignment.calendarEventIdentifier != newIdentifier {
            assignment.calendarEventIdentifier = newIdentifier
            await CloudKitManager.shared.update(assignment)
        }
    }
      
    /// Event notes in the app's language: the chore description (or "Room chore") and its estimated duration.
    private func eventNotes(for chore: ChoreModel, separator: String) -> String {
        let description = chore.localizedDescription.isEmpty ? L10n.tr("Tarefa do cômodo") : chore.localizedDescription
        return description + separator + L10n.tr("Duração estimada: \(Int(chore.duration)) min")
    }

    /// Removes a calendar event using identifier-first lookup with title and date fallback matching.
    func removeEvent(identifier: String?, title: String, date: Date?) {
        // Try direct removal via identifier
        if let identifier, let event = store.calendarItem(withIdentifier: identifier) as? EKEvent {
            do {
                try store.remove(event, span: .thisEvent, commit: true)
                return
            } catch {
                // Ignore failure and fallback
            }
        }
        
        // Search and delete orphan events matching title and date range
        guard let date else { return }
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return }
        
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)
        
        for event in events {
            if event.title == title || event.title == title.localizedDefault {
                try? store.remove(event, span: .thisEvent, commit: true)
            }
        }
    }
}
