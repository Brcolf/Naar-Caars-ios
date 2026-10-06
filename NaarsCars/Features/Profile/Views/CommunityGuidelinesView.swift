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
                    Text("guidelines_title".localized)
                        .font(.naarsTitle)
                        .fontWeight(.bold)
                    
                    Text("guidelines_review_message".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                // The six guidelines, from the localized list shared with the acceptance screen
                CommunityGuidelinesList()
            }
            .padding()
        }
        .navigationTitle("guidelines_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showDismissButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common_done".localized) {
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

// MARK: - Guideline Text

/// One community guideline: its number and the string-catalog keys for its title and body
struct CommunityGuideline: Identifiable {
    let number: Int
    let titleKey: String
    let bodyKey: String

    var id: Int { number }

    /// The guidelines members accept on first use and can re-read in Settings. Both screens
    /// render this one list, so their wording cannot drift apart, and the text comes from the
    /// string catalog instead of English literals.
    static let all: [CommunityGuideline] = [
        CommunityGuideline(number: 1, titleKey: "guidelines_1_title", bodyKey: "guidelines_1_body"),
        CommunityGuideline(number: 2, titleKey: "guidelines_2_title", bodyKey: "guidelines_2_body"),
        CommunityGuideline(number: 3, titleKey: "guidelines_3_title", bodyKey: "guidelines_3_body"),
        CommunityGuideline(number: 4, titleKey: "guidelines_4_title", bodyKey: "guidelines_4_body"),
        CommunityGuideline(number: 5, titleKey: "guidelines_5_title", bodyKey: "guidelines_5_body"),
        CommunityGuideline(number: 6, titleKey: "guidelines_6_title", bodyKey: "guidelines_6_body")
    ]
}

/// The numbered guideline sections with a divider between each pair.
/// Place it inside a leading-aligned VStack; it adds its rows to that stack.
struct CommunityGuidelinesList: View {
    var body: some View {
        ForEach(CommunityGuideline.all) { guideline in
            GuidelineSection(
                number: "\(guideline.number)",
                title: guideline.titleKey.localized,
                content: guideline.bodyKey.localized
            )

            if guideline.number != CommunityGuideline.all.last?.number {
                Divider()
            }
        }
    }
}

#Preview {
    NavigationStack {
        CommunityGuidelinesView()
    }
}


