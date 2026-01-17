//
//  MessageInputBar.swift
//  NaarsCars
//
//  Chat input bar component
//

import SwiftUI
import PhotosUI

/// Chat input bar component
struct MessageInputBar: View {
    @Binding var text: String
    @Binding var imageToSend: UIImage?
    let onSend: () -> Void
    let onImagePickerTapped: () -> Void
    let isDisabled: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Image preview (if image is selected)
            if let image = imageToSend {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .cornerRadius(8)
                    
                    Button(action: { imageToSend = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .background(Color.white.clipShape(Circle()))
                    }
                    .offset(x: -20, y: -40)
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // Input row
            HStack(spacing: 12) {
                Button(action: onImagePickerTapped) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundColor(.naarsPrimary)
                }
                
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
        }
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
    }
}

#Preview {
    MessageInputBar(
        text: .constant(""),
        imageToSend: .constant(nil),
        onSend: {},
        onImagePickerTapped: {},
        isDisabled: true
    )
}





