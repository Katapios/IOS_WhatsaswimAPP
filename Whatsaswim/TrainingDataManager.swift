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
        // Проверяем доступность App Group
        if let sharedDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) {
            self.userDefaults = sharedDefaults
            print("✅ App Group '\(AppConfig.appGroupIdentifier)' успешно инициализирован (iPhone)")
            
            // Проверяем, есть ли данные в App Group
            if let data = sharedDefaults.data(forKey: resultsKey) {
                print("📦 Найдены данные в App Group (размер: \(data.count) байт)")
            } else {
                print("⚠️ Данные в App Group не найдены. Ключ: \(resultsKey)")
            }
        } else {
            // Fallback на стандартный UserDefaults, если App Group недоступен
            print("❌ App Group '\(AppConfig.appGroupIdentifier)' недоступен. Проверьте:")
            print("   1. App Group добавлен в Capabilities для обоих таргетов (iPhone и Watch)")
            print("   2. Идентификатор App Group совпадает: '\(AppConfig.appGroupIdentifier)'")
            print("   3. App Group добавлен в entitlements файлы")
            print("   Используется стандартный UserDefaults (синхронизация не будет работать)")
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
        
        print("📅 Загружено дат с тренировками: \(dates.count)")
        if !dates.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            let datesString = dates.map { dateFormatter.string(from: $0) }.joined(separator: ", ")
            print("   Даты: \(datesString)")
        }
        
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
        // Принудительно синхронизируем перед чтением
        userDefaults.synchronize()
        
        guard let data = userDefaults.data(forKey: resultsKey) else {
            print("⚠️ Данные не найдены в App Group для ключа: \(resultsKey)")
            return []
        }
        
        guard let results = try? JSONDecoder().decode([SavedTrainingResult].self, from: data) else {
            print("❌ Ошибка декодирования данных из App Group")
            // Попробуем вывести размер данных для отладки
            print("   Размер данных: \(data.count) байт")
            return []
        }
        
        print("✅ Загружено результатов тренировок: \(results.count)")
        return results
    }
    
    // MARK: - Refresh Data
    func refresh() {
        // Принудительно синхронизируем UserDefaults для App Group
        userDefaults.synchronize()
        loadTrainingDates()
    }
    
    // MARK: - Get All Results
    func getAllResults() -> [SavedTrainingResult] {
        return loadAllResults()
    }
}

