//
//  MessagesListView.swift
//  NaarsCars
//
//  Messages list view (placeholder)
//

import SwiftUI

/// Messages list view - placeholder for conversations
struct MessagesListView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Messages")
                    .font(.title)
                    .padding()
                
                Text("Your conversations will appear here")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Messages")
        }
    }
}

#Preview {
    MessagesListView()
}

