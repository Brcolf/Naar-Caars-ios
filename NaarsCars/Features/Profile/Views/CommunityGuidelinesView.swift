//
//  CommunityGuidelinesView.swift
//  NaarsCars
//
//  Community guidelines view with scrollable content
//

import SwiftUI

/// View displaying the Naar's Cars community guidelines
struct CommunityGuidelinesView: View {
    @Environment(\.dismiss) private var dismiss
    var showDismissButton: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Community Guidelines")
                        .font(.naarsTitle)
                        .fontWeight(.bold)
                    
                    Text("Welcome to Naar's Cars! Please review these guidelines to ensure our community remains safe, supportive, and helpful.")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                // Guideline 1
                GuidelineSection(
                    number: "1",
                    title: "This is a safe, respectful, and supportive community",
                    content: """
                    Naar's Cars is a place to ask for and offer help—whether that's a ride to the airport, borrowing a tool, help moving something heavy, running an errand, or similar neighborly favors.
                    Requests are welcome, and no judgment will be passed for asking.
                    """
                )
                
                Divider()
                
                // Guideline 2
                GuidelineSection(
                    number: "2",
                    title: "Be flexible and considerate",
                    content: """
                    When possible, flexibility helps everyone. You're encouraged to suggest or accept reasonable alternatives—such as meeting at a nearby location, adjusting timing, or breaking a request into smaller parts.
                    There's no shame in asking, and no obligation for others to say yes.
                    """
                )
                
                Divider()
                
                // Guideline 3
                GuidelineSection(
                    number: "3",
                    title: "Participation is always optional",
                    content: """
                    No one is required to respond or help. If your request doesn't get a response, please don't take it personally—people may be busy, unavailable, or simply unable to help at that time.
                    """
                )
                
                Divider()
                
                // Guideline 4
                GuidelineSection(
                    number: "4",
                    title: "Reciprocity is encouraged, not enforced",
                    content: """
                    You are not required to give help in order to receive it. That said, Naar's Cars works best when members contribute when they're able.
                    If you consistently receive help without offering it when possible, others may be less inclined to respond—so please pay it forward when you can.
                    """
                )
                
                Divider()
                
                // Guideline 5
                GuidelineSection(
                    number: "5",
                    title: "Keep requests reasonable and lawful",
                    content: """
                    Requests should be legal, safe, and appropriate for a community setting. Members should never feel pressured to take on work, risk, or responsibility they're uncomfortable with.
                    """
                )
                
                Divider()
                
                // Guideline 6
                GuidelineSection(
                    number: "6",
                    title: "Communicate clearly and respectfully",
                    content: """
                    Be clear about what you're asking for, when you need help, and any relevant details. Treat others with kindness and respect—gratitude goes a long way in building trust.
                    """
                )
            }
            .padding()
        }
        .navigationTitle("Community Guidelines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showDismissButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Guideline Section

struct GuidelineSection: View {
    let number: String
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Number and Title
            HStack(alignment: .top, spacing: 12) {
                Text(number)
                    .font(.naarsTitle2)
                    .fontWeight(.bold)
                    .foregroundColor(.naarsAccent)
                    .frame(width: 30, alignment: .leading)
                
                Text(title)
                    .font(.naarsHeadline)
                    .fontWeight(.semibold)
            }
            
            // Content
            Text(content)
                .font(.naarsBody)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        CommunityGuidelinesView()
    }
}


