//
//  StarRatingView.swift
//  NaarsCars
//
//  Star rating display component
//

import SwiftUI

/// Star rating view displaying 1-5 stars with partial fill support
struct StarRatingView: View {
    let rating: Double
    var size: CGFloat = 16
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: starIcon(for: index))
                    .foregroundColor(.yellow)
                    .font(.system(size: size))
            }
        }
    }
    
    private func starIcon(for index: Int) -> String {
        let fullStars = Int(rating)
        let hasHalfStar = rating - Double(fullStars) >= 0.5
        
        if index <= fullStars {
            return "star.fill"
        } else if index == fullStars + 1 && hasHalfStar {
            return "star.lefthalf.fill"
        } else {
            return "star"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        StarRatingView(rating: 5.0)
        StarRatingView(rating: 4.5)
        StarRatingView(rating: 3.0)
        StarRatingView(rating: 2.5)
        StarRatingView(rating: 1.0)
        StarRatingView(rating: 0.0)
    }
    .padding()
}





