//
//  GuidelinesAcceptanceSheet.swift
//  NaarsCars
//
//  Sheet requiring users to accept community guidelines on first use
//

import SwiftUI

/// Non-dismissible sheet requiring user to accept community guidelines
struct GuidelinesAcceptanceSheet: View {
    /// Saves the acceptance and closes the cover. Returns false when the save failed.
    let onAccept: () async -> Bool

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
                                
                                Text("guidelines_welcome".localized)
                                    .font(.naarsTitle)
                                    .fontWeight(.bold)
                                
                                Text("guidelines_before_you_begin".localized)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                            
                            // The same six guidelines as CommunityGuidelinesView, from the one
                            // localized list, so members accept them in their own language.
                            CommunityGuidelinesList()

                            // Bottom detection view with GeometryReader
                            GeometryReader { geo in
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                                    .onAppear {
                                        AppLogger.info("profile", "Guidelines bottom marker appeared - user scrolled to end")
                                        hasScrolledToBottom = true
                                    }
                                    .onChange(of: geo.frame(in: .named("scroll")).minY) { oldValue, newValue in
                                        // Bottom element is visible when its minY is less than the visible area
                                        // Typically visible area is ~800 points, so if minY < 1000, it's visible
                                        AppLogger.info("profile", "Guidelines bottom marker minY: \(newValue)")
                                        if newValue < 1000 {
                                            AppLogger.info("profile", "User scrolled to bottom, enabling accept button")
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
                        AppLogger.info("profile", "Guidelines ScrollView appeared - user must scroll to bottom to accept")
                    }
                
                Divider()
                
                // Accept Button (bottom)
                VStack(spacing: 12) {
                    if !hasScrolledToBottom {
                        Text("guidelines_scroll_to_continue".localized)
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
                            Text("guidelines_i_accept".localized)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(!hasScrolledToBottom || isAccepting)
                    .accessibilityIdentifier("guidelines.accept")
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
            }
            .navigationTitle("guidelines_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled() // Prevent swipe to dismiss
        }
        .alert("guidelines_accept_failed".localized, isPresented: $showError) {
            Button("common_retry".localized) {
                Task {
                    await acceptGuidelines()
                }
            }
            Button("common_cancel".localized, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "guidelines_accept_failed_message".localized)
        }
    }

    private func acceptGuidelines() async {
        guard !isAccepting else { return }
        isAccepting = true
        defer { isAccepting = false }

        // On success the caller closes this cover. On failure the button used to blink and
        // leave the member here with no explanation, so say what happened and offer a retry.
        let accepted = await onAccept()
        if !accepted {
            errorMessage = "guidelines_accept_failed_message".localized
            showError = true
        }
    }

}

#Preview {
    GuidelinesAcceptanceSheet {
        AppLogger.info("profile", "Guidelines accepted")
        return true
    }
}

