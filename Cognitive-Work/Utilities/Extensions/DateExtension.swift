//
//  DateExtension.swift
//  Cognitive-Work
//
//  Created by anshu Li on 23/09/26.
//

import Foundation

extension Date {
    /// First day of the week according to the device calendar (1 = Sunday, 2 = Monday...).
    /// Ex.: device set to start the week on Sunday → `1`
    static var firstDayOfWeek = Calendar.current.firstWeekday
    
    /// Weekday abbreviations in uppercase, without a dot, reordered to start at `firstDayOfWeek`.
    /// Ex.: week starting on Sunday (pt_BR) → ["DOM", "SEG", "TER", "QUA", "QUI", "SEX", "SÁB"]
    /// Ex.: week starting on Monday → ["SEG", "TER", "QUA", "QUI", "SEX", "SÁB", "DOM"]
    static var capitalizedFirstLettersOfWeekdays: [String] {
        var calendar = Calendar.current
        calendar.locale = L10n.locale
        // Adjusted for the different weekday starts
        var weekdays = calendar.shortWeekdaySymbols
        if firstDayOfWeek > 1 {
            for _ in 1..<firstDayOfWeek {
                if let first = weekdays.first {
                    weekdays.append(first)
                    weekdays.removeFirst()
                }
            }
        }
        return weekdays.map { $0.capitalized.uppercased().replacingOccurrences(of: ".", with: "")  }
    }
    
    /// First day of the date's month, at midnight.
    /// Ex.: Oct 15, 2026 → Oct 1, 2026 00:00
    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)!.start
    }
    
    /// Last day of the date's month.
    /// Ex.: Oct 15, 2026 → Oct 31, 2026
    var endOfMonth: Date {
        let lastDay = Calendar.current.dateInterval(of: .month, for: self)!.end
        return Calendar.current.date(byAdding: .day, value: -1, to: lastDay)!
    }
    
    /// Number of days in the date's month.
    /// Ex.: Oct 15, 2026 → 31 | Feb 10, 2026 → 28
    var numberOfDaysInMonth: Int {
        Calendar.current.component(.day, from: endOfMonth)
    }
    
    /// First day shown in the calendar grid, which may belong to the previous month
    /// (the day the first row of the week starts on).
    /// Ex.: Oct 2026 starts on a Thursday; week starting on Sunday → Sep 27, 2026
    /// Ex.: week starting on Monday → Sep 28, 2026
    var firstWeekDayBeforeStart: Date {
        let startOfMonthWeekday = Calendar.current.component(.weekday, from: startOfMonth)
        var numberFromPreviousMonth = startOfMonthWeekday - Self.firstDayOfWeek
        if numberFromPreviousMonth < 0 {
            numberFromPreviousMonth += 7 // Adjust to a 0-6 range if negative
        }
        return Calendar.current.date(byAdding: .day, value: -numberFromPreviousMonth, to: startOfMonth)!
    }
    
    /// Days used to build the calendar grid: leading days from the previous month
    /// that complete the first week + every day of the current month.
    /// Ex.: Oct 2026 (week starting on Sunday) → [Sep 27, Sep 28, Sep 29, Sep 30, Oct 1, Oct 2, ... Oct 31]
    var calendarDisplayDays: [Date] {
        var days: [Date] = []
        // Start with days from the previous month to fill the grid
        let firstDisplayDay = firstWeekDayBeforeStart
        var day = firstDisplayDay
        while day < startOfMonth {
            days.append(day)
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        // Add days of the current month
        for dayOffset in 0..<numberOfDaysInMonth {
            if let newDay = Calendar.current.date(byAdding: .day, value: dayOffset, to: startOfMonth) {
                days.append(newDay)
            }
        }
        return days
    }
    
    /// Month number (1 to 12).
    /// Ex.: Oct 15, 2026 → 10
    var monthInt: Int {
        Calendar.current.component(.month, from: self)
    }
    
    /// Same date at 00:00.
    /// Ex.: Sep 30, 2026 15:45 → Sep 30, 2026 00:00
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    /// Date in ISO 8601 format, day only (no time).
    /// Ex.: Sep 30, 2026 15:45 → "2026-09-30"
    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: self)
    }
    
    /// Full date and time in ISO 8601 format, in the current time zone.
    /// Ex.: Sep 30, 2026 15:45 (Brasília) → "2026-09-30T15:45:00-03:00"
    var formattedDateHourCombined: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: self)
    }
    
    /// Transform Date to String, convert to the form you want
    /// Ex.: toString(format: "dd/MM/yyyy") → "30/09/2026"
    /// Ex.: toString(format: "HH:mm") → "15:45"
    /// - Parameter format: Receives the date format you want
    /// - Returns: Return Date in String
    func toString(format: String) -> String{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        return dateFormatter.string(from: self)
    }
    
    /// Day and abbreviated month in the app's language, without a dot.
    /// Ex.: Sep 28, 2026 → "28 set" (pt-BR) | "28 sept" (es) | "Sep 28" (en)
    var shortDayMonth: String {
        let formatter = DateFormatter.dayMonth
        if formatter.locale != L10n.locale {
            formatter.locale = L10n.locale
            // Portuguese and Spanish put the day first ("28 set", "28 sept").
            let language = L10n.locale.language.languageCode
            if language == .portuguese || language == .spanish {
                formatter.dateFormat = "d MMM"
            } else {
                formatter.setLocalizedDateFormatFromTemplate("MMMd")
            }
        }
        return formatter
            .string(from: self)
            .replacingOccurrences(of: ".", with: "")
    }
    
    /// Returns a day of the current week (week starting on Monday),
    /// shifted by `offset` days from Monday.
    /// Ex.: today is Wednesday, Sep 30, 2026 → offset 0 = Monday Sep 28 | offset 2 = Wednesday Sep 30 | offset 6 = Sunday Oct 4
    func weekdayInCurrentWeek(offset: Int, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: self)?.start ?? self
        return cal.date(byAdding: .day, value: offset, to: start) ?? start
    }
}

private extension DateFormatter {
    /// Reused formatter (creating a DateFormatter is expensive) for "day + abbreviated month".
    /// Its locale and format are set by `shortDayMonth` to match the app's language.
    /// Ex.: Sep 28, 2026 → "28 set." (the dot is removed in `shortDayMonth`)
    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
