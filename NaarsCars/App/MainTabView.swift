//
//  MainTabView.swift
//  NaarsCars
//
//  Main tab-based navigation for authenticated users
//

import SwiftUI

/// Main tab view with 5 tabs for authenticated users
/// Matches FR-038 from prd-foundation-architecture.md
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Requests", systemImage: "car.fill")
                }
            
            MessagesListView()
                .tabItem {
                    Label("Messages", systemImage: "message.fill")
                }
            
            NotificationsListView()
                .tabItem {
                    Label("Notifications", systemImage: "bell.fill")
                }
            
            LeaderboardView()
                .tabItem {
                    Label("Leaderboard", systemImage: "trophy.fill")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}

#Preview {
    MainTabView()
}

