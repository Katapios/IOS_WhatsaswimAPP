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
    
    @State private var elapsedTime: TimeInterval = 0
    @State private var isPaused = false
    @State private var timer: Timer?
    @State private var showResults = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                // Время тренировки
                Text(formatTime(elapsedTime))
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .padding(.top, 2)
                
                // Температура воды
                HStack {
                    Image(systemName: "thermometer")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("Вода")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f°C", sensorManager.waterTemperature))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                
                // Глубина погружения
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("Глубина")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f м", sensorManager.depth))
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
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        Text(isPaused ? "Продолжить" : "Пауза")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isPaused ? .green : .orange)
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
                startTimer()
                sensorManager.startMonitoring()
            }
            .onDisappear {
                stopTimer()
                sensorManager.stopMonitoring()
                sensorManager.reset()
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
    
    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if !isPaused {
                elapsedTime += 1
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            sensorManager.stopMonitoring()
        } else {
            sensorManager.startMonitoring()
        }
    }
    
    private func endTraining() {
        stopTimer()
        showResults = true
    }
    
    private func generateResults() -> SwimResults {
        let trainingData = sensorManager.getTrainingData()
        
        // Группируем гребки по стилям и сегментам 25м
        // В реальном приложении это будет более сложная логика
        let strokesPer25m = estimateStrokesPer25m(
            totalStrokes: trainingData.strokeCount,
            distance: trainingData.distance
        )
        
        let styles = [
            SwimStyle(
                name: trainingData.style,
                totalStrokes: trainingData.strokeCount,
                segments25m: strokesPer25m
            )
        ]
        
        return SwimResults(
            duration: elapsedTime,
            distance: trainingData.distance,
            waterTemperature: sensorManager.waterTemperature,
            averageDepth: sensorManager.depth,
            styles: styles
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

