//
//  DayOfWeekDTO.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 25/08/26.
//

import SwiftUI

/// One day of the week on the free time screen, with the free time the user picked for it.
///
/// Only lives on screen; the choice is saved as ``AvailableTimeModel`` records.
@Observable
class DayOfWeekDTO {
    /// The day's full name (for example, "Segunda").
    let name: String
    /// The day's short name (for example, "Seg").
    let nameAbbreviation: String
    /// The free time chosen for this day.
    var freeTime: FreeTimeEnum = .none
    
    /// Creates a day with no free time chosen yet.
    init(name: String, nameAbbreviation: String) {
        self.name = name
        self.nameAbbreviation = nameAbbreviation
    }
}
