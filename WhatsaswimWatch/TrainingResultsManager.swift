//
//  TrainingResultsManager.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import Foundation

extension Notification.Name {
    static let trainingResultsSaved = Notification.Name("trainingResultsSaved")
}

class TrainingResultsManager {
    static let shared = TrainingResultsManager()
    
    private let userDefaults = UserDefaults.standard
    private let resultsKey = "savedTrainingResults"
    
    private init() {}
    
    // MARK: - Save Results
    func saveResults(_ results: SwimResults) {
        var allResults = loadAllResults()
        
        // Создаем запись с текущей датой
        let resultEntry = SavedTrainingResult(
            date: Date(),
            results: results
        )
        
        allResults.append(resultEntry)
        
        // Сохраняем
        if let encoded = try? JSONEncoder().encode(allResults) {
            userDefaults.set(encoded, forKey: resultsKey)
            // Отправляем уведомление о сохранении результатов
            NotificationCenter.default.post(name: .trainingResultsSaved, object: nil)
        }
    }
    
    // MARK: - Load Results
    func loadTodayResults() -> SwimResults? {
        let allResults = loadAllResults()
        
        // Ищем результаты за сегодня
        if let todayResult = allResults.first(where: { result in
            Calendar.current.isDate(result.date, inSameDayAs: Date())
        }) {
            return todayResult.results
        }
        
        return nil
    }
    
    func hasTrainingToday() -> Bool {
        return loadTodayResults() != nil
    }
    
    func loadAllResults() -> [SavedTrainingResult] {
        guard let data = userDefaults.data(forKey: resultsKey),
              let results = try? JSONDecoder().decode([SavedTrainingResult].self, from: data) else {
            return []
        }
        return results
    }
    
    // MARK: - Clear Old Results (опционально, для очистки старых данных)
    func clearOldResults(olderThanDays: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) ?? Date()
        var allResults = loadAllResults()
        allResults = allResults.filter { $0.date >= cutoffDate }
        
        if let encoded = try? JSONEncoder().encode(allResults) {
            userDefaults.set(encoded, forKey: resultsKey)
        }
    }
}

// MARK: - Saved Training Result Model
struct SavedTrainingResult: Codable {
    let date: Date
    let results: SwimResults
}

// MARK: - Make SwimResults Codable
extension SwimResults: Codable {
    enum CodingKeys: String, CodingKey {
        case duration
        case distance
        case waterTemperature
        case averageDepth
        case styles
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distance = try container.decode(Double.self, forKey: .distance)
        waterTemperature = try container.decode(Double.self, forKey: .waterTemperature)
        averageDepth = try container.decode(Double.self, forKey: .averageDepth)
        styles = try container.decode([SwimStyle].self, forKey: .styles)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(duration, forKey: .duration)
        try container.encode(distance, forKey: .distance)
        try container.encode(waterTemperature, forKey: .waterTemperature)
        try container.encode(averageDepth, forKey: .averageDepth)
        try container.encode(styles, forKey: .styles)
    }
}

extension SwimStyle: Codable {
    enum CodingKeys: String, CodingKey {
        case name
        case totalStrokes
        case segments25m
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        totalStrokes = try container.decode(Int.self, forKey: .totalStrokes)
        segments25m = try container.decode([Int].self, forKey: .segments25m)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(totalStrokes, forKey: .totalStrokes)
        try container.encode(segments25m, forKey: .segments25m)
    }
}

