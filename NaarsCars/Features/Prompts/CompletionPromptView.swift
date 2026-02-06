//
//  CompletionPromptView.swift
//  NaarsCars
//
//  Completion prompt view for asking users if their request is complete
//

import SwiftUI

struct CompletionPromptView: View {
    let prompt: CompletionPrompt
    let onConfirm: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsSuccess)

                Text("common_is_this_complete".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)

                Text(prompt.requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.naarsCardBackground)
                    .cornerRadius(8)

                VStack(spacing: 12) {
                    PrimaryButton(title: "common_confirm_completed".localized) {
                        onConfirm()
                    }
                    SecondaryButton(title: "common_not_yet".localized) {
                        onSnooze()
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("common_complete_request".localized)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
    }
}
