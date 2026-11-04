//
//  WeatherViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 17/09/26.
//

import Foundation
// WeatherKit desativado (App Review 5.2.5 - atribuição Apple Weather pendente). Descomente para reativar.
//import WeatherKit
//import CoreLocation

//@Observable
//class WeatherViewModel {
//    var averageTemperature: String = "--"
//    var weatherIcon: String = "thermometer"
    
//    private let weatherService = WeatherService.shared
    
//    /// Feches today's forecast and calculates the average temperature and weather icon
//    func fetchTodaysForecast(latitude: Double, longitude: Double) async {
//        let location = CLLocation(latitude: latitude, longitude: longitude)
        
//        do {
//            let dailyForecast = try await weatherService.weather(for: location, including: .daily)
            
//            if let today = dailyForecast.first {
                
//                // MARK: - Calculate Average Temperature
//                let maxima = today.highTemperature.value
//                let minima = today.lowTemperature.value
//                let valorMedio = (maxima + minima) / 2
                
//                // Formatting in degrees
//                let mediaMeasurement = Measurement(value: valorMedio, unit: today.highTemperature.unit)
                
//                // Extracting symbol name
//                let symbol = today.symbolName
                
//                // MARK: - Updating properties
//                self.averageTemperature = mediaMeasurement.formatted(.measurement(width: .abbreviated, usage: .weather))
//                self.weatherIcon = symbol
//            }
//        } catch {
//            print("Failed to load weather: \(error.localizedDescription)")
//            self.weatherIcon = "exclamationmark.triangle"
//        }
//    }
//}
