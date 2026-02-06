//
//  AvatarView.swift
//  NaarsCars
//
//  User avatar with AsyncImage and initials fallback
//

import SwiftUI

/// Avatar view with image loading and initials fallback
struct AvatarView: View {
    let imageUrl: String?
    let name: String
    var size: CGFloat = 50
    
    private var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        } else if !components.isEmpty {
            return String(components[0].prefix(2))
        }
        return "??"
    }
    
    var body: some View {
        Group {
            if let imageUrl = imageUrl, !imageUrl.isEmpty {
                CachedAsyncImage(
                    url: URL(string: imageUrl),
                    placeholder: { ProgressView() },
                    errorView: { initialsView }
                )
                .aspectRatio(contentMode: .fill)
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("Avatar for \(name)")
    }
    
    private var initialsView: some View {
        Text(initials.uppercased())
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color.naarsPrimary)
            .clipShape(Circle())
    }
}

#Preview {
    HStack(spacing: 20) {
        AvatarView(imageUrl: nil, name: "John Doe")
        AvatarView(imageUrl: nil, name: "Jane Smith", size: 80)
        AvatarView(imageUrl: "https://example.com/avatar.jpg", name: "Bob Johnson")
    }
    .padding()
}

