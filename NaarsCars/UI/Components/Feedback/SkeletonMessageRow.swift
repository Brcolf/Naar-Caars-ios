//
//  SkeletonMessageRow.swift
//  NaarsCars
//
//  Skeleton loading component for message rows
//

import SwiftUI

/// Skeleton loading view for message rows in conversations
struct SkeletonMessageRow: View {
    let isFromCurrentUser: Bool
    
    init(isFromCurrentUser: Bool = false) {
        self.isFromCurrentUser = isFromCurrentUser
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isFromCurrentUser {
                // Avatar skeleton
                SkeletonCircle(size: 32)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Message text skeleton
                SkeletonRectangle(width: CGFloat.random(in: 100...200), height: 40, cornerRadius: 12)
                
                // Timestamp skeleton
                SkeletonRectangle(width: 60, height: 12, cornerRadius: 4)
            }
            
            if isFromCurrentUser {
                // Avatar skeleton
                SkeletonCircle(size: 32)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack(spacing: 12) {
        SkeletonMessageRow(isFromCurrentUser: false)
        SkeletonMessageRow(isFromCurrentUser: true)
        SkeletonMessageRow(isFromCurrentUser: false)
    }
    .padding()
}


