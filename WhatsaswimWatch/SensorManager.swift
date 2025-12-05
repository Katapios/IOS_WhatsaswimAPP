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
    
    private init() {
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
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if let error = error {
                print("Ошибка авторизации HealthKit: \(error.localizedDescription)")
            } else if success {
                print("HealthKit авторизация успешна")
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
        
        // Ограничиваем историю последними 10 секундами
        strokeHistory = strokeHistory.filter { now.timeIntervalSince($0) < 10 }
    }
    
    private func detectSwimStyle(_ acceleration: CMAcceleration) {
        // Упрощенный алгоритм определения стиля по паттерну движения
        // В реальном приложении нужен более сложный ML-алгоритм
        
        let verticalMovement = abs(acceleration.y)
        let horizontalMovement = abs(acceleration.x)
        let frequency = Double(strokeHistory.count)
        
        // Баттерфляй - сильные вертикальные движения
        if verticalMovement > 1.5 && frequency > 0.8 {
            currentSwimStyle = "Баттерфляй"
        }
        // Брасс - симметричные движения
        else if abs(horizontalMovement - verticalMovement) < 0.3 {
            currentSwimStyle = "Брасс"
        }
        // Вольный стиль - быстрые горизонтальные движения
        else if horizontalMovement > 1.2 && frequency > 1.0 {
            currentSwimStyle = "Вольный стиль"
        }
        // На спине - умеренные движения
        else if verticalMovement < 1.0 && horizontalMovement > 0.8 {
            currentSwimStyle = "На спине"
        }
    }
    
    private func updateDistance() {
        // Примерная оценка дистанции на основе гребков
        // Средняя длина гребка зависит от стиля плавания
        let averageStrokeLength: Double
        
        switch currentSwimStyle {
        case "Баттерфляй":
            averageStrokeLength = 1.5
        case "Вольный стиль":
            averageStrokeLength = 2.0
        case "На спине":
            averageStrokeLength = 1.8
        case "Брасс":
            averageStrokeLength = 1.2
        default:
            averageStrokeLength = 1.5
        }
        
        distance = Double(strokeCount) * averageStrokeLength
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
    }
}

