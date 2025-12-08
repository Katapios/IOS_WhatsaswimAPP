//
//  WatchConnectivityManager.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import Foundation
import WatchConnectivity

class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()
    
    private var session: WCSession?
    
    private var isActivated = false
    private var pendingResults: [SavedTrainingResult] = []
    private let activationQueue = DispatchQueue(label: "com.whatsaswim.wcsession.activation")
    
    override init() {
        super.init()
        print("[Watch] WCSession.isSupported(): \(WCSession.isSupported())")
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            
            print("🔄 Инициализация WCSession на часах...")
            print("   - Текущее состояние: \(WCSession.default.activationState.rawValue)")
            
            // Активируем на главном потоке
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let session = self.session else { return }
                
                // Проверяем, не активирован ли уже
                if session.activationState == .notActivated {
                    print("🔄 Активация WCSession...")
                    session.activate()
                } else {
                    print("ℹ️ WCSession уже в состоянии: \(session.activationState.rawValue)")
                }
            }
        } else {
            print("❌ WCSession не поддерживается на этом устройстве (watchOS)")
        }
    }
    
    // MARK: - Send Training Results to iPhone
    func sendTrainingResults(_ result: SavedTrainingResult) {
        // Всегда сохраняем в App Group (основной механизм)
        saveToAppGroup(result)
        
        // Пытаемся отправить через WatchConnectivity (дополнительный механизм)
        guard let session = session else {
            print("⚠️ WCSession не инициализирован, данные сохранены в App Group")
            return
        }
        
        // Проверяем, что сессия активирована
        if session.activationState == .activated {
            // Отправляем данные
            sendResultNow(result)
        } else {
            print("⚠️ WCSession не активирован (состояние: \(session.activationState.rawValue)), данные сохранены в App Group")
            // Сохраняем в очередь для отправки позже
            saveToQueue(result)
            
            // Пытаемся активировать сессию, если еще не активирована
            if session.activationState == .notActivated {
                DispatchQueue.main.async {
                    session.activate()
                }
            }
        }
    }
    
    // MARK: - Save to App Group (основной механизм синхронизации)
    private func saveToAppGroup(_ result: SavedTrainingResult) {
        guard let userDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) else {
            print("❌ Не удалось получить доступ к App Group")
            return
        }
        
        var allResults = loadAllResultsFromAppGroup(userDefaults)
        
        // Проверяем, есть ли уже результаты за сегодня
        let todayStart = Calendar.current.startOfDay(for: result.date)
        if let existingIndex = allResults.firstIndex(where: { result in
            Calendar.current.startOfDay(for: result.date) == todayStart
        }) {
            allResults[existingIndex] = result
        } else {
            allResults.append(result)
        }
        
        // Сортируем по дате (новые сначала)
        allResults.sort { $0.date > $1.date }
        
        // Сохраняем
        if let encoded = try? JSONEncoder().encode(allResults) {
            userDefaults.set(encoded, forKey: AppConfig.trainingResultsKey)
            print("✅ Данные сохранены в App Group")
        }
    }
    
    private func loadAllResultsFromAppGroup(_ userDefaults: UserDefaults) -> [SavedTrainingResult] {
        guard let data = userDefaults.data(forKey: AppConfig.trainingResultsKey),
              let results = try? JSONDecoder().decode([SavedTrainingResult].self, from: data) else {
            return []
        }
        return results
    }
    
    private func sendResultNow(_ result: SavedTrainingResult) {
        guard let session = session, session.activationState == .activated else {
            saveToQueue(result)
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            
            // Всегда используем updateApplicationContext - он работает даже когда iPhone не в зоне доступа
            let context: [String: Any] = [
                "type": "trainingResult",
                "data": data
            ]
            
                do {
                    try session.updateApplicationContext(context)
                    print("✅ Данные сохранены в контекст приложения для передачи на iPhone (размер: \(data.count) байт)")
                } catch {
                    print("❌ Ошибка обновления контекста приложения: \(error.localizedDescription)")
                    // Если updateApplicationContext не работает, пробуем sendMessage
                    if session.isReachable {
                        print("🔄 Пробуем отправить через sendMessage...")
                        let message: [String: Any] = [
                            "type": "trainingResult",
                            "data": data
                        ]
                        
                        session.sendMessage(message, replyHandler: { reply in
                            print("✅ Данные успешно отправлены на iPhone через sendMessage: \(reply)")
                        }, errorHandler: { error in
                            print("❌ Ошибка отправки данных на iPhone: \(error.localizedDescription)")
                            self.saveToQueue(result)
                        })
                    } else {
                        print("⚠️ iPhone недоступен, сохраняем в очередь")
                        saveToQueue(result)
                    }
                }
        } catch {
            print("❌ Ошибка кодирования данных: \(error.localizedDescription)")
            saveToQueue(result)
        }
    }
    
    // MARK: - Send All Results to iPhone
    func sendAllResults(_ results: [SavedTrainingResult]) {
        guard let session = session, session.activationState == .activated else {
            print("⚠️ WCSession не активирован")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(results)
            
            if session.isReachable {
                let message: [String: Any] = [
                    "type": "allTrainingResults",
                    "data": data
                ]
                
                session.sendMessage(message, replyHandler: { reply in
                    print("✅ Все данные успешно отправлены на iPhone")
                }, errorHandler: { error in
                    print("❌ Ошибка отправки всех данных на iPhone: \(error.localizedDescription)")
                })
            } else {
                let context: [String: Any] = [
                    "type": "allTrainingResults",
                    "data": data
                ]
                
                try session.updateApplicationContext(context)
                print("✅ Все данные сохранены в контекст приложения")
            }
        } catch {
            print("❌ Ошибка кодирования всех данных: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Queue Management
    private func saveToQueue(_ result: SavedTrainingResult) {
        var queue = loadQueue()
        queue.append(result)
        // Ограничиваем очередь 10 элементами
        if queue.count > 10 {
            queue.removeFirst(queue.count - 10)
        }
        
        if let userDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier),
           let encoded = try? JSONEncoder().encode(queue) {
            userDefaults.set(encoded, forKey: "watchConnectivityQueue")
        }
    }
    
    private func loadQueue() -> [SavedTrainingResult] {
        guard let userDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier),
              let data = userDefaults.data(forKey: "watchConnectivityQueue") else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let queue = try? decoder.decode([SavedTrainingResult].self, from: data) else {
            return []
        }
        return queue
    }
    
    func sendQueuedResults() {
        let queue = loadQueue()
        guard !queue.isEmpty else { return }
        
        guard let session = session, session.activationState == .activated else {
            print("⚠️ WCSession не активирован, очередь не отправлена")
            return
        }
        
        print("📤 Отправка \(queue.count) результатов из очереди...")
        for result in queue {
            sendResultNow(result)
        }
        
        // Очищаем очередь после отправки
        if let userDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) {
            userDefaults.removeObject(forKey: "watchConnectivityQueue")
            print("✅ Очередь очищена")
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("❌ Ошибка активации WCSession: \(error.localizedDescription)")
                self.isActivated = false
            } else {
                print("✅ WCSession активирован на часах, состояние: \(activationState.rawValue)")
                self.isActivated = (activationState == .activated)
                
                if activationState == .activated {
                    print("✅ WCSession готов к передаче данных")
                    // Пытаемся отправить данные из очереди
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.sendQueuedResults()
                    }
                    
                    // Отправляем ожидающие результаты
                    for result in self.pendingResults {
                        self.sendResultNow(result)
                    }
                    self.pendingResults.removeAll()
                } else {
                    print("⚠️ WCSession не активирован, состояние: \(activationState.rawValue)")
                }
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            print("✅ iPhone стал доступен")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.sendQueuedResults()
            }
        } else {
            print("⚠️ iPhone недоступен (данные сохранены в App Group)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let type = message["type"] as? String else {
            print("⚠️ Сообщение от iPhone без типа")
            return
        }
        
        switch type {
        case "clearTrainings":
            let scope = (message["scope"] as? String) ?? "all"
            print("🗑 [Watch] Получена команда очистки тренировок от iPhone, scope=\(scope)")
            if scope == "today" {
                TrainingResultsManager.shared.clearTodayResults()
            } else {
                TrainingResultsManager.shared.clearAllResults()
            }
        default:
            print("⚠️ [Watch] Неизвестный тип сообщения: \(type)")
        }
    }
}
