//
//  TypingIndicatorView.swift
//  NaarsCars
//
//  Animated typing indicator component (iMessage-style)
//

import SwiftUI
internal import Combine

/// Animated typing indicator bubble (iMessage-style dots)
struct TypingIndicatorView: View {
    let typingUsers: [TypingUser]
    
    @State private var animationOffset: Int = 0
    
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if !typingUsers.isEmpty {
            HStack(alignment: .bottom, spacing: 8) {
                // Avatar(s) of typing user(s)
                avatarStack
                
                VStack(alignment: .leading, spacing: 2) {
                    // Typing user name(s)
                    Text(typingText)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Animated dots bubble
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color(.systemGray3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(animationOffset == index ? 1.2 : 0.8)
                                .opacity(animationOffset == index ? 1.0 : 0.5)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        BubbleShape(isFromCurrentUser: false, showTail: true)
                            .fill(Color(.systemGray5))
                    )
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    animationOffset = (animationOffset + 1) % 3
                }
            }
        }
    }
    
    // MARK: - Avatar Stack
    
    private var avatarStack: some View {
        ZStack {
            ForEach(Array(typingUsers.prefix(3).enumerated()), id: \.element.id) { index, user in
                AvatarView(
                    imageUrl: user.avatarUrl,
                    name: user.name,
                    size: 28
                )
                .offset(x: CGFloat(index * 12))
                .zIndex(Double(3 - index))
            }
        }
        .frame(width: 28 + CGFloat(min(typingUsers.count - 1, 2) * 12))
    }
    
    // MARK: - Typing Text
    
    private var typingText: String {
        switch typingUsers.count {
        case 1:
            return "\(typingUsers[0].name) is typing..."
        case 2:
            return "\(typingUsers[0].name) and \(typingUsers[1].name) are typing..."
        case 3:
            return "\(typingUsers[0].name), \(typingUsers[1].name) and 1 other are typing..."
        default:
            let others = typingUsers.count - 2
            return "\(typingUsers[0].name), \(typingUsers[1].name) and \(others) others are typing..."
        }
    }
}

// MARK: - Compact Typing Indicator

/// Smaller typing indicator for inline use
struct CompactTypingIndicator: View {
    @State private var animationOffset: Int = 0
    
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(animationOffset == index ? 1.3 : 0.8)
                    .opacity(animationOffset == index ? 1.0 : 0.4)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                animationOffset = (animationOffset + 1) % 3
            }
        }
    }
}

// MARK: - Preview

#Preview("Single User Typing") {
    VStack {
        TypingIndicatorView(typingUsers: [
            TypingUser(id: UUID(), name: "John Doe", avatarUrl: nil)
        ])
        .padding()
    }
    .background(Color.naarsBackgroundSecondary)
}

#Preview("Multiple Users Typing") {
    VStack {
        TypingIndicatorView(typingUsers: [
            TypingUser(id: UUID(), name: "John", avatarUrl: nil),
            TypingUser(id: UUID(), name: "Jane", avatarUrl: nil)
        ])
        .padding()
        
        TypingIndicatorView(typingUsers: [
            TypingUser(id: UUID(), name: "John", avatarUrl: nil),
            TypingUser(id: UUID(), name: "Jane", avatarUrl: nil),
            TypingUser(id: UUID(), name: "Bob", avatarUrl: nil),
            TypingUser(id: UUID(), name: "Alice", avatarUrl: nil)
        ])
        .padding()
    }
    .background(Color.naarsBackgroundSecondary)
}

#Preview("Compact Indicator") {
    HStack {
        Text("Someone is typing")
            .font(.caption)
            .foregroundColor(.secondary)
        CompactTypingIndicator()
    }
    .padding()
}

