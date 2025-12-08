//
//  WatchConnectivityManager.swift
//  Whatsaswim
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import Foundation
import WatchConnectivity
import Combine

class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()
    
    private var session: WCSession?
    private let trainingDataManager = TrainingDataManager.shared
    
    override init() {
        super.init()
        print("[iPhone] WCSession.isSupported(): \(WCSession.isSupported())")
        if WCSession.isSupported() {
            let defaultSession = WCSession.default
            print("[iPhone] Initial activationState: \(defaultSession.activationState.rawValue)")
            session = defaultSession
            session?.delegate = self
            print("[iPhone] Calling WCSession.activate()")
            session?.activate()
        } else {
            print("[iPhone] WCSession is NOT supported on this device")
        }
    }
    
    // MARK: - Clear Trainings on Watch
    func sendClearCommand(scope: String) {
        guard let session = session else {
            print("⚠️ WCSession не инициализирован")
            return
        }
        
        let message: [String: Any] = [
            "type": "clearTrainings",
            "scope": scope
        ]
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("❌ Ошибка отправки команды очистки на часы: \(error.localizedDescription)")
            }
        } else {
            do {
                try session.updateApplicationContext(message)
                print("✅ Команда очистки (scope=\(scope)) сохранена в контекст приложения для передачи на часы")
            } catch {
                print("❌ Ошибка сохранения команды очистки в контекст: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Request All Data from Watch (опционально, для ручного запроса)
    func requestAllData() {
        guard let session = session else {
            print("⚠️ WCSession не инициализирован")
            return
        }
        
        guard session.activationState == .activated else {
            print("⚠️ WCSession не активирован")
            return
        }
        
        guard session.isReachable else {
            print("⚠️ Apple Watch недоступен")
            return
        }
        
        guard session.isWatchAppInstalled else {
            print("⚠️ Приложение на часах не установлено")
            return
        }
        
        let message: [String: Any] = [
            "type": "requestAllData"
        ]
        
        session.sendMessage(message, replyHandler: { reply in
            if let data = reply["data"] as? Data {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let results = try? decoder.decode([SavedTrainingResult].self, from: data) {
                    self.processReceivedResults(results)
                }
            }
        }, errorHandler: { error in
            print("❌ Ошибка запроса данных с часов: \(error.localizedDescription)")
        })
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[iPhone] activationDidCompleteWith state=\(activationState.rawValue), error=\(String(describing: error))")
        if let error = error {
            print("❌ Ошибка активации WCSession: \(error.localizedDescription)")
        } else {
            print("✅ WCSession активирован на iPhone, состояние: \(activationState.rawValue)")
            
            if activationState == .activated {
                // После активации пробуем сразу обработать полученный контекст, если он уже есть
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.checkApplicationContext()
                }
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("⚠️ WCSession стал неактивным")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("⚠️ WCSession деактивирован, переактивация...")
        session.activate()
    }
    
    // MARK: - Receive Message from Watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        processMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        processMessage(message)
        
        // Отвечаем на запрос всех данных
        if message["type"] as? String == "requestAllData" {
            let allResults = trainingDataManager.getAllResults()
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(allResults)
                replyHandler(["data": data])
            } catch {
                replyHandler(["error": error.localizedDescription])
            }
        } else {
            replyHandler(["status": "received"])
        }
    }
    
    // MARK: - Receive Application Context from Watch
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("✅ Получен контекст приложения от часов (ключей: \(applicationContext.count))")
        // Проверяем, что контекст не пустой
        if applicationContext.isEmpty {
            print("⚠️ Контекст приложения пустой")
            return
        }
        print("📦 Ключи в контексте: \(applicationContext.keys.joined(separator: ", "))")
        
        // Обрабатываем сообщение на главном потоке
        DispatchQueue.main.async {
            self.processMessage(applicationContext)
        }
    }
    
    // MARK: - Get Application Context (для проверки наличия данных)
    func checkApplicationContext() {
        guard let session = session, session.activationState == .activated else {
            return
        }
        
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            print("📦 Найден контекст приложения: \(context.keys.joined(separator: ", "))")
            processMessage(context)
        }
    }
    
    // MARK: - Process Received Message
    private func processMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else {
            print("⚠️ Сообщение не содержит тип")
            return
        }
        
        switch type {
        case "trainingResult":
            if let data = message["data"] as? Data {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let result = try? decoder.decode(SavedTrainingResult.self, from: data) {
                    processReceivedResult(result)
                } else {
                    print("❌ Ошибка декодирования результата тренировки")
                }
            } else {
                print("⚠️ Сообщение trainingResult не содержит данных")
            }
            
        case "allTrainingResults":
            if let data = message["data"] as? Data {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let results = try? decoder.decode([SavedTrainingResult].self, from: data) {
                    processReceivedResults(results)
                } else {
                    print("❌ Ошибка декодирования всех результатов тренировок")
                }
            } else {
                print("⚠️ Сообщение allTrainingResults не содержит данных")
            }
            
        case "clearTrainings":
            let scope = (message["scope"] as? String) ?? "all"
            print("🗑 Получена команда очистки тренировок с часов, scope=\(scope)")
            if scope == "today" {
                trainingDataManager.clearTodayResults()
            } else {
                trainingDataManager.clearAllResults()
            }
        default:
            print("⚠️ Неизвестный тип сообщения: \(type)")
            break
        }
    }
    
    // MARK: - Process Single Result
    private func processReceivedResult(_ result: SavedTrainingResult) {
        // Сохраняем результат в App Group UserDefaults
        saveResultToUserDefaults(result)
        
        // Обновляем данные в TrainingDataManager
        DispatchQueue.main.async {
            self.trainingDataManager.refresh()
            // Отправляем уведомление для обновления UI
            NotificationCenter.default.post(name: .trainingResultsSaved, object: nil)
        }
        
        print("✅ Получен результат тренировки от часов: \(result.date)")
    }
    
    // MARK: - Process Multiple Results
    private func processReceivedResults(_ results: [SavedTrainingResult]) {
        // Сохраняем все результаты в App Group UserDefaults
        saveAllResultsToUserDefaults(results)
        
        // Обновляем данные в TrainingDataManager
        DispatchQueue.main.async {
            self.trainingDataManager.refresh()
            // Отправляем уведомление для обновления UI
            NotificationCenter.default.post(name: .trainingResultsSaved, object: nil)
        }
        
        print("✅ Получено \(results.count) результатов тренировок от часов")
    }
    
    // MARK: - Save to UserDefaults
    private func saveResultToUserDefaults(_ result: SavedTrainingResult) {
        guard let userDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) else {
            print("❌ Не удалось получить доступ к App Group")
            return
        }
        
        var allResults = loadAllResultsFromUserDefaults(userDefaults)
        
        // Разрешаем несколько тренировок в день, но не дублируем одну и ту же (с тем же самым временем)
        if let existingIndex = allResults.firstIndex(where: { $0.date == result.date }) {
            allResults[existingIndex] = result
        } else {
            allResults.append(result)
        }
        
        // Сортируем по дате (новые сначала)
        allResults.sort { $0.date > $1.date }
        
        // Сохраняем
        if let encoded = try? JSONEncoder().encode(allResults) {
            userDefaults.set(encoded, forKey: AppConfig.trainingResultsKey)
        }
    }
    
    private func saveAllResultsToUserDefaults(_ results: [SavedTrainingResult]) {
        guard let userDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) else {
            print("❌ Не удалось получить доступ к App Group")
            return
        }
        
        // Объединяем с существующими результатами, разрешая несколько тренировок в день,
        // но не создавая дубликаты с одинаковым временем date
        var existingResults = loadAllResultsFromUserDefaults(userDefaults)
        for newResult in results {
            if let existingIndex = existingResults.firstIndex(where: { $0.date == newResult.date }) {
                existingResults[existingIndex] = newResult
            } else {
                existingResults.append(newResult)
            }
        }
        
        // Сортируем по дате (новые сначала)
        existingResults.sort { $0.date > $1.date }
        
        // Сохраняем
        if let encoded = try? JSONEncoder().encode(existingResults) {
            userDefaults.set(encoded, forKey: AppConfig.trainingResultsKey)
        }
    }
    
    private func loadAllResultsFromUserDefaults(_ userDefaults: UserDefaults) -> [SavedTrainingResult] {
        guard let data = userDefaults.data(forKey: AppConfig.trainingResultsKey),
              let results = try? JSONDecoder().decode([SavedTrainingResult].self, from: data) else {
            return []
        }
        return results
    }
}
