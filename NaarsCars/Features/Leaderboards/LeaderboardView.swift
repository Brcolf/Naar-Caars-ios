//
//  LeaderboardView.swift
//  NaarsCars
//
//  Leaderboard view (placeholder)
//

import SwiftUI

/// Leaderboard view - placeholder for community leaderboard
struct LeaderboardView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Leaderboard")
                    .font(.title)
                    .padding()
                
                Text("Community leaderboard will appear here")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Leaderboard")
        }
    }
}

#Preview {
    LeaderboardView()
}

