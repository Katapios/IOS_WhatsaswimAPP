//
//  WhatsaswimApp.swift
//  Whatsaswim
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

@main
struct WhatsaswimApp: App {
    init() {
        // Инициализируем WatchConnectivityManager при запуске приложения
        _ = WatchConnectivityManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
