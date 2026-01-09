//
//  UserAvatarLink.swift
//  NaarsCars
//
//  Avatar component with navigation to profile
//

import SwiftUI

/// Avatar view wrapped in NavigationLink to profile
struct UserAvatarLink: View {
    let profile: Profile
    var size: CGFloat = 50
    
    var body: some View {
        NavigationLink(destination: PublicProfileView(userId: profile.id)) {
            AvatarView(
                imageUrl: profile.avatarUrl,
                name: profile.name,
                size: size
            )
        }
    }
}

#Preview {
    NavigationStack {
        UserAvatarLink(
            profile: Profile(
                id: UUID(),
                name: "John Doe",
                email: "john@example.com"
            )
        )
    }
}




