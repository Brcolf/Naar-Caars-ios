//
//  MainTabView.swift
//  NaarsCars
//
//  Main tab-based navigation for authenticated users
//

import SwiftUI

/// Main tab view with 6 tabs for authenticated users
/// Matches FR-038 from prd-foundation-architecture.md
struct MainTabView: View {
    @StateObject private var notificationsViewModel = NotificationsListViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Combined dashboard with rides and favors
            DashboardTabView()
                .tag(0)
                .tabItem {
                    Label("Requests", systemImage: "car.fill")
                }
            
            ConversationsListView()
                .tag(1)
                .tabItem {
                    Label("Messages", systemImage: "message.fill")
                }
            
            NotificationsListView()
                .tag(2)
                .badge(notificationsViewModel.unreadCount > 0 ? String(notificationsViewModel.unreadCount) : nil)
                .tabItem {
                    Label("Notifications", systemImage: "bell.fill")
                }
            
            TownHallFeedView()
                .tag(3)
                .tabItem {
                    Label("Town Hall", systemImage: "house.fill")
                }
            
            LeaderboardView()
                .tag(4)
                .tabItem {
                    Label("Leaderboard", systemImage: "trophy.fill")
                }
            
            MyProfileView()
                .tag(5)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .onChange(of: navigationCoordinator.selectedTab) { _, newTab in
            selectedTab = newTab.rawValue
        }
        .onChange(of: selectedTab) { _, newTab in
            // Update coordinator when user manually changes tab
            if let tab = NavigationCoordinator.Tab(rawValue: newTab) {
                navigationCoordinator.selectedTab = tab
            }
        }
    }
}

/// Combined dashboard tab showing both rides and favors
struct DashboardTabView: View {
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Dashboard", selection: $selectedTab) {
                    Text("Rides").tag(0)
                    Text("Favors").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                TabView(selection: $selectedTab) {
                    RidesDashboardView()
                        .tag(0)
                    
                    FavorsDashboardView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Requests")
            .onChange(of: navigationCoordinator.navigateToRide) { _, _ in
                // Switch to rides tab when navigating to a ride
                if navigationCoordinator.navigateToRide != nil {
                    selectedTab = 0
                }
            }
            .onChange(of: navigationCoordinator.navigateToFavor) { _, _ in
                // Switch to favors tab when navigating to a favor
                if navigationCoordinator.navigateToFavor != nil {
                    selectedTab = 1
                }
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
