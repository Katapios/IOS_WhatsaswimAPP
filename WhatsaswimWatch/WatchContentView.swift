//
//  WatchContentView.swift
//  WhatsaswimWatch
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct WatchContentView: View {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

#Preview {
    WatchContentView()
}

