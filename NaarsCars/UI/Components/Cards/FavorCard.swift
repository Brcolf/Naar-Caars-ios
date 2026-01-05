//
//  FavorCard.swift
//  NaarsCars
//
//  Card component for displaying favor requests (skeleton)
//

import SwiftUI

/// Card component for displaying favor requests
/// This is a skeleton implementation - will be expanded in favor requests feature
struct FavorCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favor Request")
                .font(.naarsHeadline)
            
            Text("Title: Help needed")
                .font(.naarsBody)
            
            Text("Location: Address")
                .font(.naarsBody)
            
            Text("Date: Jan 1, 2025")
                .font(.naarsCaption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    FavorCard()
        .padding()
}

