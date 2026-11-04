//
//  TimeScore.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 22/09/26.
//

import Foundation

/// Points a chore is worth, based on how long it takes.
///
/// Longer chores give more points. The raw value is the number of points.
enum TimeScore: Int {
    /// Up to 5 minutes.
    case fiveMinutesScore = 3
    /// Up to 10 minutes.
    case tenMinutesScore = 6
    /// Up to 20 minutes.
    case twentyMinutesScore = 9
    /// Up to 30 minutes.
    case thirtyMinutesScore = 12
    /// Up to 40 minutes.
    case fortyMinutesScore = 15
    /// Up to 50 minutes.
    case fiftyMinutesScore = 18
    /// Up to 60 minutes.
    case sixtyMinutesScore = 21
    
    /// Points for a chore that takes `time` minutes.
    ///
    /// - Parameter time: The chore's duration, in minutes.
    /// - Returns: The points of the first range the duration fits in, or `0` for chores longer than 60 minutes.
    static func getPoints(time: Double) -> Int {
        if time <= 5 {
            return fiveMinutesScore.rawValue
        }
        else if time <= 10 {
            return tenMinutesScore.rawValue
        }
        else if time <= 20 {
            return twentyMinutesScore.rawValue
        }
        else if time <= 30 {
            return thirtyMinutesScore.rawValue
        }
        else if time <= 40 {
            return fortyMinutesScore.rawValue
        }
        else if time <= 50 {
            return fiftyMinutesScore.rawValue
        }
        else if time <= 60 {
            return sixtyMinutesScore.rawValue
        }
        return 0
    }
}
