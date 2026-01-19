//
//  CommunityTabView.swift
//  NaarsCars
//
//  Unified Community view combining Town Hall and Leaderboard
//

import SwiftUI

/// Unified Community tab that combines Town Hall and Leaderboard
struct CommunityTabView: View {
    @State private var selectedView: CommunityView = .townHall
    
    enum CommunityView: String, CaseIterable {
        case townHall = "Town Hall"
        case leaderboard = "Leaderboard"
        
        var localizedKey: String {
            switch self {
            case .townHall: return "community_town_hall"
            case .leaderboard: return "community_leaderboard"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View toggle tabs at the top
                Picker("Community View", selection: $selectedView) {
                    ForEach(CommunityView.allCases, id: \.self) { view in
                        Text(view.rawValue).tag(view)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // Content based on selection
                Group {
                    switch selectedView {
                    case .townHall:
                        TownHallFeedView()
                            .id("townHall") // Force view recreation when switching
                    case .leaderboard:
                        LeaderboardView()
                            .id("leaderboard") // Force view recreation when switching
                    }
                }
            }
            .navigationTitle("Community")
            .onAppear {
                // Clear community badge when viewing Community tab
                BadgeCountManager.shared.clearCommunityBadge()
            }
            .trackScreen("Community")
        }
    }
}

#Preview {
    CommunityTabView()
        .environmentObject(AppState())
}


