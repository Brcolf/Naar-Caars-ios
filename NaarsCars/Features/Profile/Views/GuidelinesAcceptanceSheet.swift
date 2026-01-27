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
                            
                            // Bottom detection view with GeometryReader
                            GeometryReader { geo in
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                                    .onAppear {
                                        print("📜 [Guidelines] Bottom marker appeared - user scrolled to end")
                                        hasScrolledToBottom = true
                                    }
                                    .onChange(of: geo.frame(in: .named("scroll")).minY) { oldValue, newValue in
                                        // Bottom element is visible when its minY is less than the visible area
                                        // Typically visible area is ~800 points, so if minY < 1000, it's visible
                                        print("📜 [Guidelines] Bottom marker minY: \(newValue)")
                                        if newValue < 1000 {
                                            print("📜 [Guidelines] ✅ User scrolled to bottom! Enabling button")
                                            hasScrolledToBottom = true
                                        }
                                    }
                            }
                            .frame(height: 1)
                        }
                        .padding()
                    }
                    .coordinateSpace(name: "scroll")
                    .accessibilityIdentifier("guidelines.scroll")
                    .onAppear {
                        print("📜 [Guidelines] ScrollView appeared - user must scroll to bottom to accept")
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
                    .accessibilityIdentifier("guidelines.accept")
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
    
}

#Preview {
    GuidelinesAcceptanceSheet {
        print("Guidelines accepted!")
    }
}

