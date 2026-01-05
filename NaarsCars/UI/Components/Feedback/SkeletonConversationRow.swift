//
//  SkeletonConversationRow.swift
//  NaarsCars
//
//  Skeleton loading component for conversation rows
//

import SwiftUI

/// Skeleton loading view for conversation rows in messages list
struct SkeletonConversationRow: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            SkeletonCircle(size: 50)
            
            VStack(alignment: .leading, spacing: 8) {
                // Name skeleton
                SkeletonRectangle(width: 120, height: 18, cornerRadius: 6)
                
                // Last message preview skeleton
                SkeletonRectangle(width: 200, height: 14, cornerRadius: 6)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Timestamp skeleton
                SkeletonRectangle(width: 50, height: 12, cornerRadius: 4)
                
                // Unread badge skeleton (optional)
                SkeletonCircle(size: 20)
            }
        }
        .padding()
    }
}

#Preview {
    VStack(spacing: 0) {
        SkeletonConversationRow()
        Divider()
        SkeletonConversationRow()
        Divider()
        SkeletonConversationRow()
    }
}

