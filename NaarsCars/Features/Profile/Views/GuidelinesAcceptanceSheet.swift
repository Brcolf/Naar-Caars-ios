//
//  GuidelinesAcceptanceSheet.swift
//  NaarsCars
//
//  Sheet requiring users to accept community guidelines on first use
//

import SwiftUI

/// Non-dismissible sheet requiring user to accept community guidelines
struct GuidelinesAcceptanceSheet: View {
    let onAccept: () async -> Void
    
    @State private var isAccepting = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var hasScrolledToBottom = false
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var currentScrollOffset: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Guidelines Content (scrollable)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Welcome Header
                        VStack(alignment: .center, spacing: 12) {
                            Image("naars_community_icon")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 100)
                            
                            Text("Welcome to Naar's Cars!")
                                .font(.naarsTitle)
                                .fontWeight(.bold)
                            
                            Text("Before you begin, please review and accept our community guidelines.")
                                .font(.naarsBody)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                        
                        // Guidelines (same as CommunityGuidelinesView but inline)
                        GuidelineSection(
                            number: "1",
                            title: "This is a safe, respectful, and supportive community",
                            content: """
                            Naar's Cars is a place to ask for and offer help—whether that's a ride to the airport, borrowing a tool, help moving something heavy, running an errand, or similar neighborly favors.
                            Requests are welcome, and no judgment will be passed for asking.
                            """
                        )
                        
                        Divider()
                        
                        GuidelineSection(
                            number: "2",
                            title: "Be flexible and considerate",
                            content: """
                            When possible, flexibility helps everyone. You're encouraged to suggest or accept reasonable alternatives—such as meeting at a nearby location, adjusting timing, or breaking a request into smaller parts.
                            There's no shame in asking, and no obligation for others to say yes.
                            """
                        )
                        
                        Divider()
                        
                        GuidelineSection(
                            number: "3",
                            title: "Participation is always optional",
                            content: """
                            No one is required to respond or help. If your request doesn't get a response, please don't take it personally—people may be busy, unavailable, or simply unable to help at that time.
                            """
                        )
                        
                        Divider()
                        
                        GuidelineSection(
                            number: "4",
                            title: "Reciprocity is encouraged, not enforced",
                            content: """
                            You are not required to give help in order to receive it. That said, Naar's Cars works best when members contribute when they're able.
                            If you consistently receive help without offering it when possible, others may be less inclined to respond—so please pay it forward when you can.
                            """
                        )
                        
                        Divider()
                        
                        GuidelineSection(
                            number: "5",
                            title: "Keep requests reasonable and lawful",
                            content: """
                            Requests should be legal, safe, and appropriate for a community setting. Members should never feel pressured to take on work, risk, or responsibility they're uncomfortable with.
                            """
                        )
                        
                        Divider()
                        
                        GuidelineSection(
                            number: "6",
                            title: "Communicate clearly and respectfully",
                            content: """
                            Be clear about what you're asking for, when you need help, and any relevant details. Treat others with kindness and respect—gratitude goes a long way in building trust.
                            """
                        )
                        
                        // Bottom marker
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                    .background(
                        GeometryReader { contentGeo in
                            Color.clear
                                .preference(key: ContentHeightPreferenceKey.self, value: contentGeo.size.height)
                        }
                    )
                    .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                        contentHeight = height
                        checkIfScrollable()
                    }
                }
                .background(
                    GeometryReader { scrollGeo in
                        let minY = scrollGeo.frame(in: .named("scroll")).minY
                        Color.clear
                            .preference(key: ScrollViewHeightPreferenceKey.self, value: scrollGeo.size.height)
                            .onChange(of: minY) { _, newMinY in
                                currentScrollOffset = -newMinY
                                checkScrollPosition()
                            }
                    }
                )
                .onPreferenceChange(ScrollViewHeightPreferenceKey.self) { height in
                    scrollViewHeight = height
                    checkIfScrollable()
                }
                .coordinateSpace(name: "scroll")
                .onAppear {
                    // Small delay to ensure layout is complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        checkIfScrollable()
                    }
                }
                
                Divider()
                
                // Accept Button (bottom)
                VStack(spacing: 12) {
                    if !hasScrolledToBottom {
                        Text("Please scroll to the bottom to continue")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        Task {
                            await acceptGuidelines()
                        }
                    }) {
                        if isAccepting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("I Accept")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasScrolledToBottom || isAccepting)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Community Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled() // Prevent swipe to dismiss
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Failed to accept guidelines")
        }
    }
    
    private func acceptGuidelines() async {
        isAccepting = true
        defer { isAccepting = false }
        
        await onAccept()
    }
    
    /// Check if content is scrollable and enable button accordingly
    private func checkIfScrollable() {
        // If content fits in view without scrolling, enable immediately
        // If content is scrollable, user must scroll to bottom
        if contentHeight > 0 && scrollViewHeight > 0 {
            if contentHeight <= scrollViewHeight + 100 {
                // Content fits or nearly fits - enable button immediately
                print("📜 [Guidelines] Content fits in view (\(contentHeight) <= \(scrollViewHeight)), enabling button")
                hasScrolledToBottom = true
            } else {
                print("📜 [Guidelines] Content requires scrolling: content=\(contentHeight), view=\(scrollViewHeight)")
            }
        }
    }
    
    /// Check current scroll position to determine if user has scrolled to bottom
    private func checkScrollPosition() {
        guard contentHeight > 0 && scrollViewHeight > 0 else { return }
        
        // Calculate scrollable height (total content - visible area)
        let scrollableHeight = contentHeight - scrollViewHeight
        
        // If already at bottom or content doesn't scroll, enable button
        if scrollableHeight <= 0 {
            if !hasScrolledToBottom {
                print("📜 [Guidelines] No scrollable content, enabling button")
                hasScrolledToBottom = true
            }
            return
        }
        
        // Check if user has scrolled within 20 points of the bottom
        let distanceFromBottom = scrollableHeight - currentScrollOffset
        
        if distanceFromBottom <= 20 {
            if !hasScrolledToBottom {
                print("📜 [Guidelines] Scrolled to bottom (offset: \(currentScrollOffset), scrollable: \(scrollableHeight)), enabling button")
                hasScrolledToBottom = true
            }
        }
    }
}

// MARK: - Preference Keys

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    GuidelinesAcceptanceSheet {
        print("Guidelines accepted!")
    }
}

