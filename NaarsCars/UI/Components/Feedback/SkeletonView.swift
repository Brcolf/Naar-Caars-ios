//
//  SkeletonView.swift
//  NaarsCars
//
//  Skeleton loading components with shimmer animation
//

import SwiftUI

/// Base skeleton view with shimmer animation
struct SkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gray background
                Color.gray.opacity(0.2)
                
                // Shimmer gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 2)
                .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
            }
        }
        .onAppear {
            withAnimation(
                Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}

/// Skeleton rectangle with shimmer animation
struct SkeletonRectangle: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    init(width: CGFloat? = nil, height: CGFloat = 20, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        SkeletonView()
            .frame(width: width, height: height)
            .cornerRadius(cornerRadius)
    }
}

/// Skeleton circle with shimmer animation
struct SkeletonCircle: View {
    let size: CGFloat
    
    init(size: CGFloat = 40) {
        self.size = size
    }
    
    var body: some View {
        SkeletonView()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

#Preview {
    VStack(spacing: 20) {
        SkeletonRectangle(width: 200, height: 20)
        SkeletonRectangle(width: 150, height: 16)
        SkeletonCircle(size: 50)
        SkeletonRectangle(width: nil, height: 100, cornerRadius: 12)
    }
    .padding()
}


