//
//  SwimTrainingView.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct SwimTrainingView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var elapsedTime: TimeInterval = 0
    @State private var isPaused = false
    @State private var timer: Timer?
    
    // Mock data - в реальном приложении это будет из датчиков
    @State private var waterTemperature: Double = 26.5
    @State private var depth: Double = 1.5
    @State private var distance: Double = 0.0
    
    var body: some View {
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
                Text("Water")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(waterTemperature, specifier: "%.1f")°C")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            
            // Глубина погружения
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("Depth")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(depth, specifier: "%.1f") m")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            
            // Дистанция
            HStack {
                Image(systemName: "figure.pool.swim")
                    .font(.system(size: 12))
                    .foregroundStyle(.cyan)
                Text("Distance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(distance, specifier: "%.0f") m")
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
                    Text(isPaused ? "Resume" : "Pause")
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
                    Text("End Training")
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
        }
        .onDisappear {
            stopTimer()
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
                // Mock: увеличиваем дистанцию каждую секунду (примерно 1 м/сек = 3.6 км/ч)
                distance += 1.0
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func togglePause() {
        isPaused.toggle()
    }
    
    private func endTraining() {
        stopTimer()
        dismiss()
    }
}

#Preview {
    SwimTrainingView()
}

