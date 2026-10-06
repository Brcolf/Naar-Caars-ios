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
                        // .secondary keeps the empty outline above 3:1 against the form row
                        .foregroundColor(star <= rating ? .naarsRating : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                // Each star says which rating it sets; the chosen one reads as selected. Separate
                // buttons (rather than one adjustable element) keep direct selection for Voice
                // Control and Switch Control.
                .accessibilityLabel("review_rating_accessibility".localized(with: "\(star)"))
                .accessibilityAddTraits(star == rating ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("review_section_rating".localized)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var rating = 0
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Rating: \(rating)")
                    .font(.naarsHeadline)
                
                StarRatingInput(rating: $rating)
                
                StarRatingInput(rating: $rating, size: 24, spacing: 2)
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}

