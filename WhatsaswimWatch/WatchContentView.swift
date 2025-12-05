//
//  WatchContentView.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct WatchContentView: View {
    @State private var hasTrainingToday = false
    @State private var showResults = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                NavigationLink(destination: SwimTrainingView()) {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.pool.swim")
                            .font(.system(size: 60))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 120, height: 120)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                
                Text("Поплыли!")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                // Кнопка просмотра результатов, если тренировка была сегодня
                if hasTrainingToday {
                    Button(action: {
                        showResults = true
                    }) {
                        HStack {
                            Image(systemName: "eye.fill")
                            Text("Результаты")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.blue)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .onAppear {
                checkTrainingToday()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingResultsSaved)) { _ in
                checkTrainingToday()
            }
            .navigationDestination(isPresented: $showResults) {
                if let todayResults = TrainingResultsManager.shared.loadTodayResults() {
                    SwimResultsView(results: todayResults)
                } else {
                    Text("Результаты не найдены")
                        .navigationTitle("Результаты")
                }
            }
        }
    }
    
    private func checkTrainingToday() {
        hasTrainingToday = TrainingResultsManager.shared.hasTrainingToday()
    }
}

#Preview {
    WatchContentView()
}

