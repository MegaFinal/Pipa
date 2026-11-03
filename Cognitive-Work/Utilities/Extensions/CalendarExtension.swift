//
//  CalendarExtension.swift
//  Cognitive-Work
//
//  Created by anshu Li on 23/09/26.
//

import Foundation


extension Calendar{
    /// The 24 hours of `day`, from midnight to 11 PM.
    func arrayHours(day: Date) -> [Date]{
        let startTime = self.startOfDay(for: day) //Returns the first moment of a given Date
        var hours: [Date] = []
        for i in 0..<24{
            if let date = Calendar.current.date(byAdding: .hour, value: i, to: startTime){
                hours.append(date)
            }
        }
        return hours
    }
    
    /// The 24 hours of today, from midnight to 11 PM.
    var hourOfDay:[Date]{
        let startTime = self.startOfDay(for: Date()) //Returns the first moment of a given Date
        var hours: [Date] = []
        for i in 0..<24{
            if let date = Calendar.current.date(byAdding: .hour, value: i, to: startTime){
                hours.append(date)
            }
        }
        return hours
    }
}
