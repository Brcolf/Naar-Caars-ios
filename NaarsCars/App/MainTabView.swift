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
            RequestsDashboardView()
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
            
            CommunityTabView()
                .tag(3)
                .tabItem {
                    Label("Community", systemImage: "person.3.fill")
                }
            
            MyProfileView()
                .tag(4)
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

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
