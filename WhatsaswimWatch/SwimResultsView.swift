//
//  SwimResultsView.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct SwimStyle {
    let name: String
    let totalStrokes: Int
    let segments25m: [Int] // Количество гребков для каждого отрезка 25м
}

struct SwimResults {
    let duration: TimeInterval
    let distance: Double
    let waterTemperature: Double
    let averageDepth: Double
    let styles: [SwimStyle]
}

struct SwimResultsView: View {
    @Environment(\.dismiss) private var dismiss
    
    let results: SwimResults
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Главные показатели
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Длительность")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(formatTime(results.duration))
                                .font(.title3)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Дистанция")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(Int(results.distance)) м")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
                
                Divider()
                
                // Стили плавания
                VStack(alignment: .leading, spacing: 16) {
                    Text("Стили плавания")
                        .font(.headline)
                        .padding(.horizontal, 8)
                    
                    ForEach(results.styles, id: \.name) { style in
                        StyleSection(style: style)
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Дополнительная информация
                VStack(alignment: .leading, spacing: 12) {
                    Text("Дополнительно")
                        .font(.headline)
                        .padding(.horizontal, 8)
                    
                    InfoRow(
                        icon: "thermometer",
                        label: "Температура воды",
                        value: String(format: "%.1f°C", results.waterTemperature),
                        color: .orange
                    )
                    
                    InfoRow(
                        icon: "arrow.down.circle",
                        label: "Средняя глубина",
                        value: String(format: "%.1f м", results.averageDepth),
                        color: .blue
                    )
                    
                    InfoRow(
                        icon: "speedometer",
                        label: "Средняя скорость",
                        value: String(format: "%.1f м/мин", calculateAverageSpeed(distance: results.distance, duration: results.duration)),
                        color: .green
                    )
                    
                    InfoRow(
                        icon: "figure.pool.swim",
                        label: "Всего гребков",
                        value: "\(results.styles.reduce(0) { $0 + $1.totalStrokes })",
                        color: .cyan
                    )
                }
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Результаты тренировки")
        .navigationBarTitleDisplayMode(.inline)
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
    
    private func calculateAverageSpeed(distance: Double, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return distance / (duration / 60.0) // метры в минуту
    }
}

struct StyleSection: View {
    let style: SwimStyle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(style.name)
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(style.totalStrokes) гребков")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            
            if !style.segments25m.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Гребков на 25м:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    
                    ForEach(Array(style.segments25m.enumerated()), id: \.offset) { index, strokes in
                        HStack {
                            Text("\(index + 1) × 25м:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(strokes) гребков")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal, 8)
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
    }
}

#Preview {
    NavigationStack {
        SwimResultsView(results: SwimResults(
            duration: 1800,
            distance: 500,
            waterTemperature: 26.5,
            averageDepth: 1.5,
            styles: [
                SwimStyle(name: "Баттерфляй", totalStrokes: 120, segments25m: [28, 30, 29, 33]),
                SwimStyle(name: "Вольный стиль", totalStrokes: 200, segments25m: [18, 19, 18, 20, 19]),
                SwimStyle(name: "На спине", totalStrokes: 150, segments25m: [22, 23, 22]),
                SwimStyle(name: "Брасс", totalStrokes: 100, segments25m: [15, 16, 15])
            ]
        ))
    }
}

