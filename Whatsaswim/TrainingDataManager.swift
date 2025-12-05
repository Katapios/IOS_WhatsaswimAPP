//
//  TrainingDataManager.swift
//  Whatsaswim
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import Foundation
import Combine

// MARK: - Shared Data Models
struct SwimStyle: Codable {
    let name: String
    let totalStrokes: Int
    let segments25m: [Int]
}

struct SwimResults: Codable {
    let duration: TimeInterval
    let distance: Double
    let waterTemperature: Double
    let averageDepth: Double
    let styles: [SwimStyle]
}

struct SavedTrainingResult: Codable {
    let date: Date
    let results: SwimResults
}

// MARK: - Training Data Manager for iPhone
class TrainingDataManager: ObservableObject {
    static let shared = TrainingDataManager()
    
    private let userDefaults: UserDefaults
    private let resultsKey = AppConfig.trainingResultsKey
    
    @Published var trainingDates: Set<Date> = []
    
    private init() {
        // Используем App Group для синхронизации с часами
        // Инициализируем UserDefaults для App Group
        let suiteName = AppConfig.appGroupIdentifier
        if let sharedDefaults = UserDefaults(suiteName: suiteName) {
            self.userDefaults = sharedDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
        loadTrainingDates()
    }
    
    // MARK: - Load Training Dates
    func loadTrainingDates() {
        let allResults = loadAllResults()
        let dates = Set(allResults.map { result in
            Calendar.current.startOfDay(for: result.date)
        })
        
        // Обновляем @Published свойство на главном потоке
        DispatchQueue.main.async { [weak self] in
            self?.trainingDates = dates
        }
    }
    
    // MARK: - Check if Date has Training
    func hasTraining(on date: Date) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: date)
        return trainingDates.contains(dayStart)
    }
    
    // MARK: - Get Training Results for Date
    func getTrainingResults(for date: Date) -> SwimResults? {
        let allResults = loadAllResults()
        let dayStart = Calendar.current.startOfDay(for: date)
        
        // Ищем результаты за указанную дату
        // Используем startOfDay для точного сравнения дат
        if let result = allResults.first(where: { result in
            Calendar.current.startOfDay(for: result.date) == dayStart
        }) {
            return result.results
        }
        
        return nil
    }
    
    // MARK: - Get Saved Result for Date
    func getSavedResult(for date: Date) -> SavedTrainingResult? {
        let allResults = loadAllResults()
        let dayStart = Calendar.current.startOfDay(for: date)
        
        // Ищем результаты за указанную дату
        return allResults.first(where: { result in
            Calendar.current.startOfDay(for: result.date) == dayStart
        })
    }
    
    // MARK: - Load All Results
    private func loadAllResults() -> [SavedTrainingResult] {
        // Читаем данные из App Group через UserDefaults
        guard let data = userDefaults.data(forKey: resultsKey) else {
            print("📭 Нет данных в App Group для ключа: \(resultsKey)")
            return []
        }
        
        guard let results = try? JSONDecoder().decode([SavedTrainingResult].self, from: data) else {
            print("❌ Ошибка декодирования данных из App Group")
            return []
        }
        
        print("✅ Загружено \(results.count) результатов из App Group")
        return results
    }
    
    // MARK: - Refresh Data
    func refresh() {
        // Принудительно перезагружаем данные из App Group
        loadTrainingDates()
    }
    
    // MARK: - Get All Results
    func getAllResults() -> [SavedTrainingResult] {
        return loadAllResults()
    }
}

