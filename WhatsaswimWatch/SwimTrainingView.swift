//
//  SwimTrainingView.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct SwimTrainingView: View {
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var sensorManager = SensorManager.shared
    @StateObject private var viewModel = SwimTrainingViewModel()
    
    @State private var showResults = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                // Время тренировки
                Text(formatTime(viewModel.elapsedTime))
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .padding(.top, 2)
                
                // Текущий стиль плавания
                HStack {
                    Image(systemName: "figure.pool.swim")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("Стиль")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(sensorManager.currentSwimStyle)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                
                // Гребки в текущем отрезке (до остановки)
                HStack {
                    Image(systemName: "hand.wave")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("Гребков в отрезке")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(sensorManager.getCurrentSegmentInfo().strokesInSegment)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                
                // Дистанция
                HStack {
                    Image(systemName: "figure.pool.swim")
                        .font(.system(size: 12))
                        .foregroundStyle(.cyan)
                    Text("Дистанция")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f м", sensorManager.distance))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                
                Spacer(minLength: 0)
                
                // Кнопка Pause
                Button(action: {
                    togglePause()
                }) {
                    HStack {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        Text(viewModel.isPaused ? "Продолжить" : "Пауза")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(viewModel.isPaused ? .green : .orange)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                
                // Кнопка End Training
                Button(action: {
                    endTraining()
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Завершить")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.red)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Если таймер еще не запущен, запускаем его
                viewModel.startTimer()
                // Если мониторинг еще не запущен, запускаем его
                // startMonitoring() проверяет, не запущен ли уже мониторинг
                sensorManager.startMonitoring()
            }
            .onDisappear {
                // НЕ вызываем reset() здесь, так как это может сбросить данные до их сохранения
                // reset() будет вызван только после завершения тренировки в endTraining()
                // Останавливаем только таймер, но не мониторинг
                viewModel.stopTimer()
                // Не останавливаем мониторинг здесь, если тренировка еще не завершена
                // sensorManager.stopMonitoring() вызывается в endTraining()
            }
            .navigationDestination(isPresented: $showResults) {
                SwimResultsView(results: generateResults())
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func togglePause() {
        viewModel.isPaused.toggle()
        if viewModel.isPaused {
            sensorManager.pauseMonitoring()
        } else {
            sensorManager.resumeMonitoring()
        }
    }
    
    private func endTraining() {
        viewModel.stopTimer()
        
        // Генерируем результаты ПЕРЕД остановкой мониторинга, чтобы получить все данные
        let results = generateResults()
        
        // Сохраняем результаты ПЕРЕД сбросом
        TrainingResultsManager.shared.saveResults(results)
        
        // Отправляем уведомление о сохранении результатов
        NotificationCenter.default.post(name: .trainingResultsSaved, object: nil)
        
        // Завершаем сессию тренировки ПОСЛЕ сохранения
        sensorManager.stopMonitoring()
        
        // Только после сохранения сбрасываем данные сенсора
        sensorManager.reset()
        
        showResults = true
    }
    
    private func generateResults() -> SwimResults {
        // Получаем все стили, которые использовались во время тренировки
        let stylesSummary = sensorManager.getStylesSummary()
        
        // Преобразуем в формат SwimStyle
        let styles = stylesSummary.map { summary in
            SwimStyle(
                name: summary.style,
                totalStrokes: summary.totalStrokes,
                segments25m: summary.segments25m
            )
        }
        
        // Если стилей не было определено или все стили имеют 0 гребков, используем общие данные
        let trainingData = sensorManager.getTrainingData()
        let hasValidStyles = !styles.isEmpty && styles.contains { $0.totalStrokes > 0 }
        
        let finalStyles: [SwimStyle]
        if !hasValidStyles && trainingData.strokeCount > 0 {
            // Используем общие данные, если стили не определены, но есть гребки
            let strokesPer25m = estimateStrokesPer25m(
                totalStrokes: trainingData.strokeCount,
                distance: trainingData.distance
            )
            finalStyles = [
                SwimStyle(
                    name: trainingData.style.isEmpty ? "Не определен" : trainingData.style,
                    totalStrokes: trainingData.strokeCount,
                    segments25m: strokesPer25m
                )
            ]
        } else if styles.isEmpty {
            // Если вообще нет данных, создаем пустую запись
            finalStyles = [
                SwimStyle(
                    name: "Не определен",
                    totalStrokes: 0,
                    segments25m: []
                )
            ]
        } else {
            // Фильтруем стили с нулевыми гребками, но оставляем хотя бы один
            let filteredStyles = styles.filter { $0.totalStrokes > 0 }
            finalStyles = filteredStyles.isEmpty ? styles : filteredStyles
        }
        
        // Используем дистанцию из всех сегментов или общую дистанцию
        let totalDistance = stylesSummary.isEmpty ? trainingData.distance : stylesSummary.reduce(0.0) { $0 + $1.totalDistance }
        let finalDistance = totalDistance > 0 ? totalDistance : trainingData.distance
        
        return SwimResults(
            duration: viewModel.elapsedTime,
            distance: finalDistance,
            waterTemperature: sensorManager.waterTemperature,
            averageDepth: sensorManager.depth,
            styles: finalStyles
        )
    }
    
    private func estimateStrokesPer25m(totalStrokes: Int, distance: Double) -> [Int] {
        guard distance > 0 else { return [] }
        
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
}

#Preview {
    SwimTrainingView()
}

