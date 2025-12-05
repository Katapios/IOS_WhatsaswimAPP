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
        var strokesPer25m: [Int] = []
    }
    
    // История всех стилей во время тренировки
    private var styleSegments: [StyleSegment] = []
    private var currentStyleSegment: StyleSegment?
    private var styleDetectionHistory: [(style: String, timestamp: Date)] = []
    private let styleChangeThreshold: TimeInterval = 3.0 // Минимум 3 секунды для смены стиля
    private let styleConfidenceWindow: TimeInterval = 5.0 // Окно для определения стиля
    
    // Workout Session для предотвращения блокировки экрана
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private let workoutDelegate = WorkoutSessionDelegate()
    private var isHealthKitAuthorized = false
    
    private init() {
        workoutDelegate.sensorManager = self
        requestHealthKitAuthorization()
    }
    
    // MARK: - HealthKit Authorization
    private func requestHealthKitAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit недоступен")
            return
        }
        
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
        
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { [weak self] success, error in
            if let error = error {
                print("Ошибка авторизации HealthKit: \(error.localizedDescription)")
                self?.isHealthKitAuthorized = false
            } else if success {
                print("HealthKit авторизация успешна")
                self?.isHealthKitAuthorized = true
            }
        }
    }
    
    // MARK: - Start Monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startTime = Date()
        strokeCount = 0
        distance = 0.0
        strokeHistory.removeAll()
        styleSegments.removeAll()
        currentStyleSegment = nil
        styleDetectionHistory.removeAll()
        
        // Запускаем сессию тренировки для предотвращения блокировки экрана
        // Важно: запускаем сессию ПЕРЕД другими мониторингами
        startWorkoutSession()
        
        startHeartRateMonitoring()
        startMotionMonitoring()
        startDepthMonitoring()
        startTemperatureMonitoring()
    }
    
    // MARK: - Stop Monitoring
    func stopMonitoring() {
        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        
        // Завершаем сессию тренировки
        endWorkoutSession()
    }
    
    // MARK: - Pause/Resume Monitoring
    func pauseMonitoring() {
        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        
        // Приостанавливаем сессию тренировки (но не завершаем, чтобы экран не блокировался)
        pauseWorkoutSession()
    }
    
    func resumeMonitoring() {
        guard workoutSession != nil else {
            // Если сессии нет, запускаем заново
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
    }
    
    // MARK: - Workout Session Management
    private func startWorkoutSession() {
        // Проверяем доступность HealthKit
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit недоступен, экран может блокироваться")
            return
        }
        
        // Создаем конфигурацию тренировки для плавания
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .swimming
        configuration.locationType = .indoor
        
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
            print("Сессия тренировки запущена, экран не должен блокироваться")
            
            // Затем начинаем сбор данных асинхронно
            workoutBuilder?.beginCollection(withStart: startDate) { [weak self] success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Ошибка начала сбора данных тренировки: \(error.localizedDescription)")
                    } else if success {
                        print("Сбор данных тренировки начат успешно")
                    } else {
                        print("Не удалось начать сбор данных тренировки")
                    }
                }
            }
        } catch {
            print("Ошибка создания сессии тренировки: \(error.localizedDescription)")
            print("Экран может блокироваться без активной сессии тренировки")
        }
    }
    
    private func pauseWorkoutSession() {
        guard let workoutSession = workoutSession else { return }
        // Приостанавливаем сессию (экран продолжит работать)
        workoutSession.pause()
    }
    
    private func resumeWorkoutSession() {
        guard let workoutSession = workoutSession else { return }
        // Возобновляем сессию
        workoutSession.resume()
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
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { success, error in
            if let error = error {
                print("Ошибка фоновой доставки пульса: \(error.localizedDescription)")
            }
        }
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
        strokeCount += 1
        
        // Добавляем гребок к текущему сегменту стиля
        if var segment = currentStyleSegment {
            segment.strokeCount += 1
            currentStyleSegment = segment
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
        let strokeFrequency = Double(recentStrokes.count) / 5.0 // гребков в секунду
        
        // Определяем предполагаемый стиль
        var detectedStyle: String = "Не определен"
        
        // Баттерфляй - сильные вертикальные движения, высокая частота
        if verticalMovement > 1.8 && strokeFrequency > 0.6 {
            detectedStyle = "Баттерфляй"
        }
        // Брасс - симметричные движения, низкая частота
        else if abs(horizontalMovement - verticalMovement) < 0.4 && strokeFrequency < 0.5 && magnitude > 0.8 {
            detectedStyle = "Брасс"
        }
        // Кроль - быстрые горизонтальные движения, высокая частота
        else if horizontalMovement > 1.3 && strokeFrequency > 0.7 {
            detectedStyle = "Кроль"
        }
        // На спине - умеренные движения, средняя частота
        else if verticalMovement < 1.2 && horizontalMovement > 0.9 && strokeFrequency > 0.4 && strokeFrequency < 0.7 {
            detectedStyle = "На спине"
        }
        
        // Добавляем в историю определения стилей
        if detectedStyle != "Не определен" {
            styleDetectionHistory.append((detectedStyle, now))
            // Ограничиваем историю последними 10 секундами
            styleDetectionHistory = styleDetectionHistory.filter { now.timeIntervalSince($0.timestamp) < 10.0 }
            
            // Определяем наиболее частый стиль за последние 5 секунд
            let recentDetections = styleDetectionHistory.filter { now.timeIntervalSince($0.timestamp) <= styleConfidenceWindow }
            let styleCounts = Dictionary(grouping: recentDetections, by: { $0.style })
                .mapValues { $0.count }
            
            if let mostCommonStyle = styleCounts.max(by: { $0.value < $1.value })?.key {
                // Если это первый стиль, создаем начальный сегмент
                if currentStyleSegment == nil && mostCommonStyle != "Не определен" {
                    changeSwimStyle(to: mostCommonStyle)
                }
                // Если стиль изменился, создаем новый сегмент
                else if mostCommonStyle != currentSwimStyle && mostCommonStyle != "Не определен" {
                    let styleDetections = recentDetections.filter { $0.style == mostCommonStyle }
                    if let firstDetection = styleDetections.first,
                       now.timeIntervalSince(firstDetection.timestamp) >= styleChangeThreshold {
                        changeSwimStyle(to: mostCommonStyle)
                    }
                }
            }
        }
    }
    
    private func changeSwimStyle(to newStyle: String) {
        let now = Date()
        
        // Завершаем текущий сегмент стиля
        if var currentSegment = currentStyleSegment {
            currentSegment.endTime = now
            // Вычисляем дистанцию для сегмента
            currentSegment.distance = calculateDistanceForSegment(segment: currentSegment)
            // Вычисляем гребки на 25м для сегмента
            currentSegment.strokesPer25m = calculateStrokesPer25m(
                totalStrokes: currentSegment.strokeCount,
                distance: currentSegment.distance
            )
            styleSegments.append(currentSegment)
        }
        
        // Начинаем новый сегмент стиля
        currentSwimStyle = newStyle
        currentStyleSegment = StyleSegment(
            style: newStyle,
            startTime: now,
            endTime: nil,
            strokeCount: 0,
            distance: 0.0,
            strokesPer25m: []
        )
        
        print("Стиль изменен на: \(newStyle)")
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
        
        distance = totalDistance
        
        // Обновляем дистанцию текущего сегмента
        if var segment = currentStyleSegment {
            segment.distance = calculateDistanceForSegment(segment: segment)
            currentStyleSegment = segment
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
        depth = 0.0
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
        waterTemperature = 26.0
        
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
            currentSegment.strokesPer25m = calculateStrokesPer25m(
                totalStrokes: currentSegment.strokeCount,
                distance: currentSegment.distance
            )
            allSegments.append(currentSegment)
        }
        
        return allSegments
    }
    
    // MARK: - Get Styles Summary
    func getStylesSummary() -> [(style: String, totalStrokes: Int, totalDistance: Double, segments25m: [Int])] {
        let allSegments = getAllStyleSegments()
        
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
        distance = 0.0
        strokeCount = 0
        heartRate = 0.0
        depth = 0.0
        waterTemperature = 0.0
        currentSwimStyle = "Не определен"
        strokeHistory.removeAll()
        surfacePressure = nil
        isCalibrated = false
        workoutSession = nil
        workoutBuilder = nil
        styleSegments.removeAll()
        currentStyleSegment = nil
        styleDetectionHistory.removeAll()
    }
}

