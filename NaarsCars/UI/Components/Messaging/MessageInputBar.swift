//
//  MessageInputBar.swift
//  NaarsCars
//
//  Chat input bar component
//

import SwiftUI

/// Chat input bar component
struct MessageInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let isDisabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit {
                    if !isDisabled {
                        onSend()
                    }
                }
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(isDisabled ? .gray : .naarsPrimary)
            }
            .disabled(isDisabled)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
    }
}

#Preview {
    MessageInputBar(
        text: .constant(""),
        onSend: {},
        isDisabled: true
    )
}




