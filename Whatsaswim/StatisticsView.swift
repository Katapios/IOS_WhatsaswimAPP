//
//  StatisticsView.swift
//  Whatsaswim
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct StatisticsView: View {
    @StateObject private var dataManager = TrainingDataManager.shared
    @State private var allResults: [SavedTrainingResult] = []
    @State private var isLoading = true
    @State private var refreshTimer: Timer?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView("Загрузка статистики...")
                        .padding()
                } else if allResults.isEmpty {
                    ContentUnavailableView {
                        Label("Нет данных о тренировках", systemImage: "chart.bar.fill")
                    } description: {
                        Text("Завершите тренировку на часах, чтобы увидеть статистику")
                    }
                    .padding()
                } else {
                    VStack(spacing: 24) {
                        // Общая статистика
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Общая статистика")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                StatCard(
                                    icon: "figure.pool.swim",
                                    label: "Всего тренировок",
                                    value: "\(allResults.count)",
                                    color: .blue
                                )
                                
                                StatCard(
                                    icon: "clock.fill",
                                    label: "Общее время",
                                    value: formatTotalTime(allResults.reduce(0) { $0 + $1.results.duration }),
                                    color: .cyan
                                )
                                
                                StatCard(
                                    icon: "ruler.fill",
                                    label: "Общая дистанция",
                                    value: "\(Int(allResults.reduce(0) { $0 + $1.results.distance })) м",
                                    color: .green
                                )
                                
                                StatCard(
                                    icon: "figure.pool.swim",
                                    label: "Всего гребков",
                                    value: "\(allResults.reduce(0) { $0 + $1.results.styles.reduce(0) { $0 + $1.totalStrokes } })",
                                    color: .orange
                                )
                            }
                            .padding(.horizontal)
                        }
                        
                        // Статистика по стилям
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Статистика по стилям")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            let styleStats = calculateStyleStatistics()
                            
                            ForEach(styleStats.sorted(by: { $0.value.totalStrokes > $1.value.totalStrokes }), id: \.key) { styleName, stats in
                                StyleStatisticsCard(styleName: styleName, stats: stats)
                            }
                        }
                        
                        // Последние тренировки
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Последние тренировки")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Spacer()
                                if allResults.count > 5 {
                                    Text("Показано 5 из \(allResults.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                            
                            ForEach(allResults.sorted(by: { $0.date > $1.date }).prefix(5), id: \.date) { result in
                                RecentTrainingCard(result: result)
                                    .onTapGesture {
                                        // При клике открываем детальный просмотр
                                        // Это можно реализовать через NavigationLink или sheet
                                    }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Статистика")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadStatistics()
            }
            .refreshable {
                dataManager.refresh()
                // Небольшая задержка для синхронизации App Group
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    loadStatistics()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingResultsSaved)) { _ in
                dataManager.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.loadStatistics()
                }
            }
        }
    }
    
    private func loadStatistics() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let results = dataManager.getAllResults()
            DispatchQueue.main.async {
                self.allResults = results
                self.isLoading = false
            }
        }
    }
    
    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak dataManager] _ in
            dataManager?.refresh()
            loadStatistics()
        }
    }
    
    private func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func formatTotalTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        
        if hours > 0 {
            return "\(hours)ч \(minutes)м"
        } else {
            return "\(minutes)м"
        }
    }
    
    private func calculateStyleStatistics() -> [String: (totalStrokes: Int, totalDistance: Double, count: Int)] {
        var stats: [String: (totalStrokes: Int, totalDistance: Double, count: Int)] = [:]
        
        for result in allResults {
            // Общий объём гребков по всем стилям в этой тренировке
            let totalStrokesAll = result.results.styles.reduce(0) { $0 + $1.totalStrokes }
            
            // Если по каким-то причинам гребков нет, распределять дистанцию нечего
            guard totalStrokesAll > 0 else { continue }
            
            for style in result.results.styles {
                // Доля дистанции для конкретного стиля пропорционально количеству гребков
                let fraction = Double(style.totalStrokes) / Double(totalStrokesAll)
                let styleDistance = result.results.distance * fraction
                
                if let existing = stats[style.name] {
                    stats[style.name] = (
                        totalStrokes: existing.totalStrokes + style.totalStrokes,
                        totalDistance: existing.totalDistance + styleDistance,
                        count: existing.count + 1
                    )
                } else {
                    stats[style.name] = (
                        totalStrokes: style.totalStrokes,
                        totalDistance: styleDistance,
                        count: 1
                    )
                }
            }
        }
        
        return stats
    }
}

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

struct StyleStatisticsCard: View {
    let styleName: String
    let stats: (totalStrokes: Int, totalDistance: Double, count: Int)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(styleName)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(stats.count) раз")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Гребков")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(stats.totalStrokes)")
                        .font(.body)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Дистанция")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(stats.totalDistance)) м")
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal)
    }
}

struct RecentTrainingCard: View {
    let result: SavedTrainingResult
    @State private var showDetail = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, HH:mm"
        return formatter
    }()
    
    var body: some View {
        Button(action: {
            showDetail = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateFormatter.string(from: result.date).capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 12) {
                        Label("\(formatTime(result.results.duration))", systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Label("\(Int(result.results.distance)) м", systemImage: "ruler.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if !result.results.styles.isEmpty {
                            Label("\(result.results.styles.count) стилей", systemImage: "list.bullet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            TrainingDetailView(date: result.date)
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
}

#Preview {
    StatisticsView()
}

