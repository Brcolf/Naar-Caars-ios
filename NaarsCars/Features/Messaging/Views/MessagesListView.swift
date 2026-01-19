//
//  MessagesListView.swift
//  NaarsCars
//
//  Messages list view - redirects to ConversationsListView
//

import SwiftUI

/// Messages list view - now redirects to full ConversationsListView
/// This file maintained for backward compatibility
struct MessagesListView: View {
    var body: some View {
        // Use the full ConversationsListView implementation
        ConversationsListView()
    }
}

#Preview {
    MessagesListView()
        .environmentObject(AppState())
}

