//
//  ContentView.swift
//  Whatsaswim
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarView()
                    .navigationTitle("Тренировки")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Календарь", systemImage: "calendar")
            }
            .tag(0)
            
            NavigationStack {
                StatisticsView()
            }
            .tabItem {
                Label("Статистика", systemImage: "chart.bar.fill")
            }
            .tag(1)
        }
    }
}

#Preview {
    ContentView()
}
