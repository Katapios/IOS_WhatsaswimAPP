//
//  WatchContentView.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct WatchContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "applewatch")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, Watch!")
        }
        .padding()
    }
}

#Preview {
    WatchContentView()
}

