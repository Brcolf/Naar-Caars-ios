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

                Text("Is This Complete?")
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)

                Text(prompt.requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                VStack(spacing: 12) {
                    PrimaryButton(title: "Confirm completed") {
                        onConfirm()
                    }
                    SecondaryButton(title: "Not yet") {
                        onSnooze()
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Complete Request")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
    }
}
