//
//  NotificationsListView.swift
//  NaarsCars
//
//  Notifications list view (placeholder)
//

import SwiftUI

/// Notifications list view - placeholder for in-app notifications
struct NotificationsListView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Notifications")
                    .font(.title)
                    .padding()
                
                Text("Your notifications will appear here")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Notifications")
        }
    }
}

#Preview {
    NotificationsListView()
}

