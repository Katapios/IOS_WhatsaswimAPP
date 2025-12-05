//
//  SensorManager.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import Foundation
import Combine
import HealthKit
import CoreMotion
import WatchKit

// MARK: - Workout Session Delegate
class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    weak var sensorManager: SensorManager?
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        let stateNames: [HKWorkoutSessionState: String] = [
            .notStarted: "notStarted",
            .running: "running",
            .paused: "paused",
            .ended: "ended"
        ]
        
        let fromName = stateNames[fromState] ?? "unknown"
        let toName = stateNames[toState] ?? "unknown"
        
        print("Состояние сессии тренировки изменилось: \(fromName) -> \(toName)")
        
        // Когда сессия становится активной, экран не будет блокироваться
        if toState == .running {
            print("✅ Сессия тренировки активна (running), экран НЕ будет блокироваться")
        } else if toState == .notStarted {
            print("⚠️ Сессия тренировки не запущена, экран может блокироваться")
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Ошибка сессии тренировки: \(error.localizedDescription)")
    }
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Обработка собранных данных
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Обработка событий тренировки
    }
}

class SensorManager: ObservableObject {
    static let shared = SensorManager()
    
    private let healthStore = HKHealthStore()
    private let motionManager = CMMotionManager()
    
    @Published var waterTemperature: Double = 0.0
    @Published var depth: Double = 0.0
    @Published var distance: Double = 0.0
    @Published var heartRate: Double = 0.0
    @Published var strokeCount: Int = 0
    @Published var currentSwimStyle: String = "Не определен"
    
    private var isMonitoring = false
    private var startTime: Date?
    private var lastAcceleration: CMAcceleration?
    private var strokeDetectionThreshold: Double = 2.0
    private var strokeHistory: [Date] = []
    private var surfacePressure: NSNumber?
    private var isCalibrated = false
    
    // Структура для отслеживания сегментов стилей
    struct StyleSegment {
        let style: String
        let startTime: Date
        var endTime: Date?
        var strokeCount: Int = 0
        var distance: Double = 0.0
        var strokesPer25m: [Int] = [] // Сегменты по 25м - записываются после каждой остановки
    }
    
    // История всех стилей во время тренировки
    private var styleSegments: [StyleSegment] = []
    private var currentStyleSegment: StyleSegment?
    private var styleDetectionHistory: [(style: String, timestamp: Date)] = []
    private let styleChangeThreshold: TimeInterval = 3.0 // Минимум 3 секунды для смены стиля
    private let styleConfidenceWindow: TimeInterval = 5.0 // Окно для определения стиля
    
    // Отслеживание остановок движения для записи сегментов 25м
    private var lastStrokeTime: Date?
    private let stopDetectionThreshold: TimeInterval = 5.0 // Остановка = нет гребков более 5 секунд
    private var currentSegmentStrokes: Int = 0 // Гребки в текущем сегменте 25м
    private var currentSegmentStartTime: Date? // Время начала текущего сегмента
    private var isStopped: Bool = false // Флаг остановки движения
    
    // Workout Session для предотвращения блокировки экрана
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private let workoutDelegate = WorkoutSessionDelegate()
    private var isHealthKitAuthorized = false
    private var authorizationRequested = false
    private var stopDetectionTimer: Timer? // Таймер для проверки остановок движения
    
    private init() {
        workoutDelegate.sensorManager = self
        // Не запрашиваем авторизацию сразу, чтобы избежать двойного запроса
        // Авторизация будет запрошена при первом запуске мониторинга
    }
    
    // MARK: - HealthKit Authorization
    private func requestHealthKitAuthorization(completion: (() -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit недоступен на этом устройстве")
            completion?()
            return
        }
        
        // Сначала проверяем текущий статус авторизации
        guard let workoutType = HKObjectType.workoutType() as? HKObjectType else {
            print("❌ Не удалось получить тип тренировки для HealthKit")
            completion?()
            return
        }
        
        let currentStatus = healthStore.authorizationStatus(for: workoutType)
        print("📊 Текущий статус авторизации HealthKit: \(currentStatus.rawValue)")
        
        // Если статус уже авторизован, не запрашиваем снова
        if currentStatus == .sharingAuthorized {
            print("✅ HealthKit уже авторизован")
            isHealthKitAuthorized = true
            completion?()
            return
        }
        
        // Если статус не определен (.notDetermined) или отклонен, запрашиваем авторизацию
        // Это гарантирует, что диалог авторизации будет показан пользователю
        print("🔐 Запрашиваем авторизацию HealthKit (статус: \(currentStatus.rawValue))...")
        authorizationRequested = true
        
        var typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
            HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!
        ]
        
        // Добавляем температуру тела, если доступна
        if let bodyTemperatureType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) {
            typesToRead.insert(bodyTemperatureType)
        }
        
        // Типы для записи данных тренировки
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
            HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!
        ]
        
        // ВАЖНО: requestAuthorization всегда показывает диалог, если статус .notDetermined
        // Даже если мы вызывали его ранее, если пользователь не ответил, диалог покажется снова
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Ошибка авторизации HealthKit: \(error.localizedDescription)")
                    self?.isHealthKitAuthorized = false
                    completion?()
                } else {
                    print("✅ Запрос авторизации HealthKit выполнен (success: \(success))")
                    // Проверяем реальный статус авторизации после запроса
                    self?.checkHealthKitAuthorizationStatus(completion: completion)
                }
            }
        }
    }
    
    private func checkHealthKitAuthorizationStatus(completion: (() -> Void)? = nil) {
        guard let workoutType = HKObjectType.workoutType() as? HKObjectType else {
            isHealthKitAuthorized = false
            print("❌ Не удалось получить тип тренировки для HealthKit")
            completion?()
            return
        }
        
        let status = healthStore.authorizationStatus(for: workoutType)
        
        // Определяем статус авторизации
        let statusDescription: String
        switch status {
        case .notDetermined:
            statusDescription = "notDetermined (не определен)"
        case .sharingDenied:
            statusDescription = "sharingDenied (отклонено)"
        case .sharingAuthorized:
            statusDescription = "sharingAuthorized (авторизовано)"
        @unknown default:
            statusDescription = "unknown (\(status.rawValue))"
        }
        
        // Для workoutType статус может быть .notDetermined, но это не значит, что мы не можем запустить сессию
        // Однако для записи данных нужен статус .sharingAuthorized
        isHealthKitAuthorized = (status == .sharingAuthorized)
        
        print("📊 Статус авторизации HealthKit для тренировок: \(statusDescription), авторизован: \(isHealthKitAuthorized)")
        
        // Если статус не определен, это нормально - пользователь еще не ответил на запрос
        if status == .notDetermined {
            print("ℹ️ Статус не определен - авторизация будет запрошена при следующем вызове")
        }
        
        completion?()
    }
    
    // MARK: - Start Monitoring
    func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ Мониторинг уже запущен")
            return
        }
        
        print("🚀 Запуск мониторинга датчиков...")
        
        // Всегда проверяем и запрашиваем авторизацию перед запуском
        // Это гарантирует, что запрос будет показан пользователю
        requestHealthKitAuthorization { [weak self] in
            print("✅ Авторизация HealthKit обработана, запускаем мониторинг")
            self?.startMonitoringInternal()
        }
    }
    
    private func startMonitoringInternal() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startTime = Date()
        strokeHistory.removeAll()
        styleSegments.removeAll()
        currentStyleSegment = nil
        styleDetectionHistory.removeAll()
        lastStrokeTime = nil
        currentSegmentStrokes = 0
        currentSegmentStartTime = Date()
        isStopped = false
        
        // Обновляем @Published свойства на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.strokeCount = 0
            self.distance = 0.0
        }
        
        // Запускаем сессию тренировки для предотвращения блокировки экрана
        // Важно: запускаем сессию ПЕРЕД другими мониторингами
        startWorkoutSession()
        
        startHeartRateMonitoring()
        startMotionMonitoring()
        startDepthMonitoring()
        startTemperatureMonitoring()
        
        // Запускаем таймер для проверки остановок движения
        startStopDetectionTimer()
    }
    
    // MARK: - Stop Monitoring
    func stopMonitoring() {
        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        
        // Останавливаем таймер проверки остановок на главном потоке
        DispatchQueue.main.async { [weak self] in
            self?.stopDetectionTimer?.invalidate()
            self?.stopDetectionTimer = nil
            
            // Записываем последний сегмент перед остановкой мониторинга
            self?.recordCurrentSegment25m()
        }
        
        // Завершаем сессию тренировки
        endWorkoutSession()
    }
    
    // MARK: - Pause/Resume Monitoring
    func pauseMonitoring() {
        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        
        // Останавливаем таймер проверки остановок на главном потоке
        DispatchQueue.main.async { [weak self] in
            self?.stopDetectionTimer?.invalidate()
            self?.stopDetectionTimer = nil
        }
        
        // Приостанавливаем сессию тренировки (но не завершаем, чтобы экран не блокировался)
        // ВАЖНО: При паузе сессия остается активной, экран не должен гаснуть
        pauseWorkoutSession()
    }
    
    func resumeMonitoring() {
        guard workoutSession != nil else {
            // Если сессии нет, запускаем заново
            print("⚠️ Сессия тренировки отсутствует при возобновлении, запускаем заново")
            startMonitoring()
            return
        }
        
        isMonitoring = true
        
        // Возобновляем сессию тренировки
        resumeWorkoutSession()
        
        startHeartRateMonitoring()
        startMotionMonitoring()
        startDepthMonitoring()
        startTemperatureMonitoring()
        
        // Возобновляем таймер проверки остановок
        startStopDetectionTimer()
    }
    
    // MARK: - Workout Session Management
    private func startWorkoutSession() {
        // Проверяем доступность HealthKit
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit недоступен, экран может блокироваться")
            return
        }
        
        print("🏃 Запуск сессии тренировки HealthKit...")
        
        // Всегда проверяем авторизацию перед запуском сессии
        // Это гарантирует, что запрос будет показан, если еще не был показан
        if !authorizationRequested || !isHealthKitAuthorized {
            print("⚠️ HealthKit авторизация не подтверждена, запрашиваем авторизацию перед запуском сессии")
            requestHealthKitAuthorization { [weak self] in
                // Запускаем сессию даже если авторизация не подтверждена
                // Сессия тренировки может работать и без полной авторизации (для предотвращения блокировки экрана)
                print("🔄 Продолжаем запуск сессии после запроса авторизации")
                self?.startWorkoutSessionInternal()
            }
            return
        }
        
        startWorkoutSessionInternal()
    }
    
    private func startWorkoutSessionInternal() {
        // Если сессия уже существует, не создаем новую
        guard workoutSession == nil else {
            print("⚠️ Сессия тренировки уже существует")
            return
        }
        
        // Создаем конфигурацию тренировки для плавания
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .swimming
        // Для плавания используем swimmingLocationType вместо locationType
        configuration.swimmingLocationType = .pool
        // Указываем длину бассейна (25 метров)
        configuration.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
        
        do {
            // Создаем сессию тренировки
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession?.delegate = workoutDelegate
            
            // Создаем builder для сбора данных тренировки
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.delegate = workoutDelegate
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            // Начинаем сессию и сбор данных
            let startDate = Date()
            
            // ВАЖНО: Сначала запускаем сессию, это предотвратит блокировку экрана
            workoutSession?.startActivity(with: startDate)
            print("✅ Сессия тренировки запущена, экран не должен блокироваться")
            
            // Затем начинаем сбор данных асинхронно
            workoutBuilder?.beginCollection(withStart: startDate) { [weak self] success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Ошибка начала сбора данных тренировки: \(error.localizedDescription)")
                    } else if success {
                        print("✅ Сбор данных тренировки начат успешно")
                    } else {
                        print("⚠️ Не удалось начать сбор данных тренировки")
                    }
                }
            }
        } catch {
            print("❌ Ошибка создания сессии тренировки: \(error.localizedDescription)")
            print("Экран может блокироваться без активной сессии тренировки")
        }
    }
    
    private func pauseWorkoutSession() {
        guard let workoutSession = workoutSession else {
            print("⚠️ Попытка приостановить несуществующую сессию тренировки")
            return
        }
        // Приостанавливаем сессию (экран продолжит работать, так как сессия все еще активна)
        workoutSession.pause()
        print("⏸️ Сессия тренировки приостановлена, экран не должен гаснуть")
    }
    
    private func resumeWorkoutSession() {
        guard let workoutSession = workoutSession else {
            print("⚠️ Попытка возобновить несуществующую сессию тренировки")
            return
        }
        // Возобновляем сессию
        workoutSession.resume()
        print("▶️ Сессия тренировки возобновлена")
    }
    
    private func endWorkoutSession() {
        guard let workoutSession = workoutSession,
              let workoutBuilder = workoutBuilder else { return }
        
        let endDate = Date()
        
        // Завершаем сбор данных
        workoutBuilder.endCollection(withEnd: endDate) { success, error in
            if let error = error {
                print("Ошибка завершения сбора данных: \(error.localizedDescription)")
            }
            
            // Завершаем сессию
            workoutSession.end()
            
            // Сохраняем тренировку
            workoutBuilder.finishWorkout { workout, error in
                if let error = error {
                    print("Ошибка сохранения тренировки: \(error.localizedDescription)")
                } else {
                    print("Тренировка сохранена в HealthKit")
                }
            }
        }
        
        self.workoutSession = nil
        self.workoutBuilder = nil
    }
    
    // MARK: - Heart Rate Monitoring
    private func startHeartRateMonitoring() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] query, completionHandler, error in
            if let error = error {
                print("Ошибка мониторинга пульса: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            self?.fetchLatestHeartRate()
            completionHandler()
        }
        
        healthStore.execute(query)
    }
    
    private func fetchLatestHeartRate() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let samples = samples as? [HKQuantitySample],
                  let sample = samples.first else { return }
            
            let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
            let value = sample.quantity.doubleValue(for: heartRateUnit)
            
            DispatchQueue.main.async {
                self?.heartRate = value
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Motion Monitoring (Accelerometer)
    private func startMotionMonitoring() {
        guard motionManager.isAccelerometerAvailable else {
            print("Акселерометр недоступен")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 0.1 // 10 Hz
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self,
                  let acceleration = data?.acceleration,
                  self.isMonitoring else { return }
            
            self.processAcceleration(acceleration)
        }
    }
    
    private func processAcceleration(_ acceleration: CMAcceleration) {
        // Вычисляем общее ускорение
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        // Определяем гребок по изменению ускорения
        if let lastAccel = lastAcceleration {
            let delta = abs(magnitude - sqrt(
                lastAccel.x * lastAccel.x +
                lastAccel.y * lastAccel.y +
                lastAccel.z * lastAccel.z
            ))
            
            if delta > strokeDetectionThreshold {
                detectStroke()
            }
        }
        
        lastAcceleration = acceleration
        
        // Определяем стиль плавания по паттерну движения
        detectSwimStyle(acceleration)
        
        // Обновляем дистанцию на основе гребков
        updateDistance()
    }
    
    private func detectStroke() {
        let now = Date()
        
        // Фильтруем слишком частые гребки (минимум 0.5 секунды между гребками)
        if let lastStroke = strokeHistory.last,
           now.timeIntervalSince(lastStroke) < 0.5 {
            return
        }
        
        strokeHistory.append(now)
        lastStrokeTime = now
        
        // Если было остановлено движение, возобновляем
        if isStopped {
            isStopped = false
            print("▶️ Движение возобновлено, начинаем новый сегмент")
            // После остановки начинаем новый сегмент
            startNewSegmentAfterStop()
        }
        
        // Обновляем @Published свойства на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.strokeCount += 1
            self.currentSegmentStrokes += 1
            
            // Добавляем гребок к текущему сегменту стиля
            if var segment = self.currentStyleSegment {
                segment.strokeCount += 1
                self.currentStyleSegment = segment
            }
        }
        
        // Ограничиваем историю последними 10 секундами
        strokeHistory = strokeHistory.filter { now.timeIntervalSince($0) < 10 }
    }
    
    private func detectSwimStyle(_ acceleration: CMAcceleration) {
        // Улучшенный алгоритм определения стиля по паттерну движения
        let now = Date()
        let verticalMovement = abs(acceleration.y)
        let horizontalMovement = abs(acceleration.x)
        let magnitude = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
        
        // Вычисляем частоту гребков за последние 5 секунд
        let recentStrokes = strokeHistory.filter { now.timeIntervalSince($0) <= 5.0 }
        let strokeFrequency = recentStrokes.count > 0 ? Double(recentStrokes.count) / 5.0 : 0.0 // гребков в секунду
        
        // Определяем предполагаемый стиль
        // ВАЖНО: Проверяем в порядке от наиболее специфичных к менее специфичным
        var detectedStyle: String = "Не определен"
        
        // Баттерфляй - очень сильные вертикальные движения, высокая частота
        if verticalMovement > 2.0 && strokeFrequency > 0.7 && horizontalMovement < 1.5 {
            detectedStyle = "Баттерфляй"
        }
        // Кроль - быстрые горизонтальные движения, высокая частота, низкая вертикальная составляющая
        else if horizontalMovement > 1.5 && strokeFrequency > 0.8 && verticalMovement < 1.3 {
            detectedStyle = "Кроль"
        }
        // На спине - умеренные движения, средняя частота, горизонтальные движения преобладают
        else if horizontalMovement > 1.0 && horizontalMovement < 1.5 && strokeFrequency > 0.5 && strokeFrequency < 0.8 && verticalMovement < 1.0 {
            detectedStyle = "На спине"
        }
        // Брасс - симметричные движения (вертикальные и горизонтальные близки), низкая частота, средняя величина
        // Более строгие условия для брасса, чтобы он не срабатывал для всех остальных стилей
        else if abs(horizontalMovement - verticalMovement) < 0.25 && strokeFrequency < 0.5 && strokeFrequency > 0.15 && magnitude > 1.0 && magnitude < 1.7 && horizontalMovement > 0.8 && verticalMovement > 0.8 {
            detectedStyle = "Брасс"
        }
        
        // Добавляем в историю определения стилей (даже если "Не определен")
        styleDetectionHistory.append((detectedStyle, now))
        // Ограничиваем историю последними 10 секундами
        styleDetectionHistory = styleDetectionHistory.filter { now.timeIntervalSince($0.timestamp) < 10.0 }
        
        // Определяем наиболее частый стиль за последние 5 секунд
        let recentDetections = styleDetectionHistory.filter { now.timeIntervalSince($0.timestamp) <= styleConfidenceWindow }
        guard !recentDetections.isEmpty else { return }
        
        let styleCounts = Dictionary(grouping: recentDetections, by: { $0.style })
            .mapValues { $0.count }
        
        // Игнорируем "Не определен" при выборе стиля, если есть другие варианты
        let validStyleCounts = styleCounts.filter { $0.key != "Не определен" }
        let mostCommonStyle = (validStyleCounts.isEmpty ? styleCounts : validStyleCounts).max(by: { $0.value < $1.value })?.key ?? "Не определен"
        
        // Если это первый стиль и есть гребки, создаем начальный сегмент
        if currentStyleSegment == nil {
            if mostCommonStyle != "Не определен" {
                changeSwimStyle(to: mostCommonStyle)
            } else if strokeCount > 0 {
                // Если стиль не определен, но есть гребки, создаем сегмент "Не определен"
                changeSwimStyle(to: "Не определен")
            }
        }
        // Если стиль изменился, создаем новый сегмент
        else if mostCommonStyle != currentSwimStyle {
            let styleDetections = recentDetections.filter { $0.style == mostCommonStyle }
            if let firstDetection = styleDetections.first,
               now.timeIntervalSince(firstDetection.timestamp) >= styleChangeThreshold {
                // Если было остановлено движение, сразу меняем стиль (не ждем порога)
                if isStopped {
                    print("🔄 Стиль изменен после остановки: \(currentSwimStyle) -> \(mostCommonStyle)")
                    changeSwimStyle(to: mostCommonStyle)
                    isStopped = false // Сбрасываем флаг остановки
                } else {
                    changeSwimStyle(to: mostCommonStyle)
                }
            }
        } else if isStopped && mostCommonStyle == currentSwimStyle {
            // Если стиль не изменился после остановки, просто сбрасываем флаг
            isStopped = false
        }
    }
    
    private func changeSwimStyle(to newStyle: String) {
        let now = Date()
        
        // Завершаем текущий сегмент стиля (но не записываем сегменты 25м здесь)
        // Сегменты 25м записываются только при остановке движения
        if var currentSegment = currentStyleSegment {
            currentSegment.endTime = now
            // Вычисляем дистанцию для сегмента
            currentSegment.distance = calculateDistanceForSegment(segment: currentSegment)
            styleSegments.append(currentSegment)
        }
        
        // Обновляем @Published свойства на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Начинаем новый сегмент стиля
            self.currentSwimStyle = newStyle
            self.currentStyleSegment = StyleSegment(
                style: newStyle,
                startTime: now,
                endTime: nil,
                strokeCount: 0,
                distance: 0.0,
                strokesPer25m: []
            )
            // Сбрасываем счетчик гребков для нового сегмента 25м
            self.currentSegmentStrokes = 0
            self.currentSegmentStartTime = now
        }
        
        print("Стиль изменен на: \(newStyle)")
    }
    
    // MARK: - Stop Detection and Segment Recording
    private func startStopDetectionTimer() {
        // Останавливаем предыдущий таймер на главном потоке
        DispatchQueue.main.async { [weak self] in
            self?.stopDetectionTimer?.invalidate()
            self?.stopDetectionTimer = nil
            
            // Создаем новый таймер на главном потоке
            self?.stopDetectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkForStop()
            }
        }
    }
    
    private func checkForStop() {
        guard isMonitoring else { return }
        
        let now = Date()
        
        // Проверяем, прошло ли более 5 секунд с последнего гребка
        if let lastStroke = lastStrokeTime {
            let timeSinceLastStroke = now.timeIntervalSince(lastStroke)
            
            if timeSinceLastStroke >= stopDetectionThreshold && !isStopped {
                // Обнаружена остановка движения
                isStopped = true
                print("⏸️ Обнаружена остановка движения (прошло \(Int(timeSinceLastStroke))с без гребков)")
                
                // Записываем текущий сегмент 25м на главном потоке
                DispatchQueue.main.async { [weak self] in
                    self?.recordCurrentSegment25m()
                    
                    // После остановки сбрасываем счетчик для нового сегмента
                    self?.currentSegmentStrokes = 0
                    self?.currentSegmentStartTime = nil
                }
            }
        } else if !isStopped {
            // Если еще не было гребков, но прошло достаточно времени - тоже считаем остановкой
            if let segmentStart = currentSegmentStartTime,
               now.timeIntervalSince(segmentStart) >= stopDetectionThreshold {
                isStopped = true
                print("⏸️ Обнаружена остановка движения (нет активности)")
            }
        }
    }
    
    private func recordCurrentSegment25m() {
        // Этот метод должен вызываться на главном потоке
        guard currentSegmentStrokes > 0, var currentSegment = currentStyleSegment else {
            return
        }
        
        // Добавляем сегмент 25м к текущему сегменту стиля
        currentSegment.strokesPer25m.append(currentSegmentStrokes)
        self.currentStyleSegment = currentSegment
        print("📝 Записан сегмент 25м: стиль '\(currentSegment.style)', гребков: \(currentSegmentStrokes)")
    }
    
    private func startNewSegmentAfterStop() {
        // После остановки начинаем новый сегмент
        // Стиль будет определен при следующем движении через detectSwimStyle
        // Обновляем на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentSegmentStrokes = 0
            self.currentSegmentStartTime = Date()
        }
        
        // После остановки стиль может измениться, поэтому ждем нового определения
        // detectSwimStyle() определит стиль при следующем движении
        print("🔄 Начинаем новый сегмент после остановки, ожидаем определения стиля")
    }
    
    private func calculateDistanceForSegment(segment: StyleSegment) -> Double {
        // Вычисляем дистанцию на основе количества гребков и стиля
        let averageStrokeLength: Double
        switch segment.style {
        case "Баттерфляй":
            averageStrokeLength = 1.5
        case "Кроль":
            averageStrokeLength = 2.0
        case "На спине":
            averageStrokeLength = 1.8
        case "Брасс":
            averageStrokeLength = 1.2
        default:
            averageStrokeLength = 1.5
        }
        return Double(segment.strokeCount) * averageStrokeLength
    }
    
    private func calculateStrokesPer25m(totalStrokes: Int, distance: Double) -> [Int] {
        guard distance > 0 && totalStrokes > 0 else { return [] }
        
        let segments = Int(distance / 25.0)
        guard segments > 0 else { return [] }
        
        let strokesPerSegment = totalStrokes / segments
        let remainder = totalStrokes % segments
        
        var result = Array(repeating: strokesPerSegment, count: segments)
        
        // Распределяем остаток
        for i in 0..<remainder {
            result[i] += 1
        }
        
        return result
    }
    
    private func updateDistance() {
        // Обновляем общую дистанцию на основе всех сегментов и текущего
        var totalDistance = styleSegments.reduce(0.0) { $0 + $1.distance }
        
        if let currentSegment = currentStyleSegment {
            let segmentDistance = calculateDistanceForSegment(segment: currentSegment)
            totalDistance += segmentDistance
        }
        
        // Обновляем @Published свойства на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.distance = totalDistance
            
            // Обновляем дистанцию текущего сегмента
            if var segment = self.currentStyleSegment {
                segment.distance = self.calculateDistanceForSegment(segment: segment)
                self.currentStyleSegment = segment
            }
        }
    }
    
    // MARK: - Depth Monitoring (Barometric Pressure)
    private func startDepthMonitoring() {
        // На watchOS используем Device Motion для определения глубины
        // через анализ ускорения по оси Z
        guard motionManager.isDeviceMotionAvailable else {
            print("Device Motion недоступен")
            return
        }
        
        // Калибруем на поверхности воды
        calibrateSurfacePressure()
        
        motionManager.deviceMotionUpdateInterval = 0.2 // 5 Hz
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self,
                  let motion = motion,
                  self.isMonitoring else { return }
            
            // Используем ускорение по Z для оценки глубины
            let verticalAcceleration = motion.userAcceleration.z
            
            if abs(verticalAcceleration) > 0.1 {
                let depthChange = abs(verticalAcceleration) * 0.05
                
                DispatchQueue.main.async {
                    if verticalAcceleration < 0 {
                        // Погружение
                        self.depth = max(0, self.depth + depthChange)
                    } else if verticalAcceleration > 0 && self.depth > 0 {
                        // Всплытие
                        self.depth = max(0, self.depth - depthChange)
                    }
                }
            }
        }
    }
    
    private func calibrateSurfacePressure() {
        // Обновляем @Published свойство на главном потоке
        DispatchQueue.main.async { [weak self] in
            self?.depth = 0.0
        }
        surfacePressure = nil
        isCalibrated = true
    }
    
    // MARK: - Water Temperature
    // Apple Watch не имеет прямого датчика температуры воды
    // Используем косвенные методы через датчик температуры корпуса
    // При погружении в воду температура корпуса быстро приближается к температуре воды
    private func startTemperatureMonitoring() {
        // Устанавливаем типичную температуру бассейна как начальное значение
        // В реальном приложении это будет обновляться при погружении
        DispatchQueue.main.async { [weak self] in
            self?.waterTemperature = 26.0
        }
        
        // Пытаемся получить температуру из HealthKit (если доступна)
        // Для watchOS 11+ можно попробовать получить данные о температуре
        // через HealthKit, если они доступны
        fetchTemperatureFromHealthKit()
    }
    
    private func fetchTemperatureFromHealthKit() {
        guard let bodyTemperatureType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) else {
            print("Тип температуры тела недоступен в HealthKit")
            DispatchQueue.main.async {
                self.waterTemperature = 26.0
            }
            return
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: bodyTemperatureType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Ошибка получения температуры из HealthKit: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.waterTemperature = 26.0
                }
                return
            }
            
            if let samples = samples as? [HKQuantitySample],
               let sample = samples.first {
                let temperatureUnit = HKUnit.degreeCelsius()
                let value = sample.quantity.doubleValue(for: temperatureUnit)
                DispatchQueue.main.async {
                    self.waterTemperature = value
                }
            } else {
                DispatchQueue.main.async {
                    self.waterTemperature = 26.0
                }
            }
        }
        healthStore.execute(query)
    }
    
    // MARK: - Get Training Data
    func getTrainingData() -> (distance: Double, strokeCount: Int, style: String) {
        return (distance, strokeCount, currentSwimStyle)
    }
    
    // MARK: - Get All Style Segments
    func getAllStyleSegments() -> [StyleSegment] {
        var allSegments = styleSegments
        
        // Добавляем текущий сегмент, если он есть
        if var currentSegment = currentStyleSegment {
            currentSegment.endTime = Date()
            currentSegment.distance = calculateDistanceForSegment(segment: currentSegment)
            
            // Если есть незаписанные гребки в текущем сегменте, добавляем их как последний сегмент 25м
            if currentSegmentStrokes > 0 {
                currentSegment.strokesPer25m.append(currentSegmentStrokes)
            }
            
            allSegments.append(currentSegment)
        }
        
        return allSegments
    }
    
    // MARK: - Get Styles Summary
    func getStylesSummary() -> [(style: String, totalStrokes: Int, totalDistance: Double, segments25m: [Int])] {
        let allSegments = getAllStyleSegments()
        
        // Если нет сегментов, но есть гребки, создаем сегмент "Не определен"
        if allSegments.isEmpty && strokeCount > 0 {
            let now = Date()
            // Используем startTime из SensorManager или текущее время как fallback
            let segmentStartTime = self.startTime ?? now
            let estimatedDistance = calculateDistanceForSegment(segment: StyleSegment(
                style: currentSwimStyle,
                startTime: segmentStartTime,
                endTime: now,
                strokeCount: strokeCount,
                distance: distance,
                strokesPer25m: []
            ))
            let strokesPer25m = calculateStrokesPer25m(
                totalStrokes: strokeCount,
                distance: estimatedDistance
            )
            return [(
                style: currentSwimStyle,
                totalStrokes: strokeCount,
                totalDistance: estimatedDistance,
                segments25m: strokesPer25m
            )]
        }
        
        // Группируем сегменты по стилям
        let groupedByStyle = Dictionary(grouping: allSegments, by: { $0.style })
        
        return groupedByStyle.map { style, segments in
            let totalStrokes = segments.reduce(0) { $0 + $1.strokeCount }
            let totalDistance = segments.reduce(0.0) { $0 + $1.distance }
            
            // Объединяем все сегменты по 25м
            var allSegments25m: [Int] = []
            for segment in segments {
                allSegments25m.append(contentsOf: segment.strokesPer25m)
            }
            
            return (style: style, totalStrokes: totalStrokes, totalDistance: totalDistance, segments25m: allSegments25m)
        }
    }
    
    func reset() {
        stopMonitoring()
        strokeHistory.removeAll()
        surfacePressure = nil
        isCalibrated = false
        workoutSession = nil
        workoutBuilder = nil
        styleSegments.removeAll()
        currentStyleSegment = nil
        styleDetectionHistory.removeAll()
        authorizationRequested = false // Сбрасываем флаг авторизации
        lastStrokeTime = nil
        isStopped = false
        
        // Останавливаем таймер и сбрасываем переменные на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopDetectionTimer?.invalidate()
            self.stopDetectionTimer = nil
            self.currentSegmentStrokes = 0
            self.currentSegmentStartTime = nil
            
            // Обновляем @Published свойства
            self.distance = 0.0
            self.strokeCount = 0
            self.heartRate = 0.0
            self.depth = 0.0
            self.waterTemperature = 0.0
            self.currentSwimStyle = "Не определен"
        }
    }
}

