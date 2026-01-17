//
//  StarRatingInput.swift
//  NaarsCars
//
//  Interactive star rating input component
//

import SwiftUI

/// Interactive star rating input component (1-5 stars)
struct StarRatingInput: View {
    @Binding var rating: Int
    var size: CGFloat = 32
    var spacing: CGFloat = 4
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                Button(action: {
                    rating = star
                }) {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundColor(star <= rating ? .yellow : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var rating = 0
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Rating: \(rating)")
                    .font(.headline)
                
                StarRatingInput(rating: $rating)
                
                StarRatingInput(rating: $rating, size: 24, spacing: 2)
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}

