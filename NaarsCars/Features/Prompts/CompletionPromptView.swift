//
//  CompletionPromptView.swift
//  NaarsCars
//
//  Completion prompt view for asking users if their request is complete
//

import SwiftUI

struct CompletionPromptView: View {
    let prompt: CompletionPrompt
    /// Send "yes, it's done" / "not yet". Both throw when the answer cannot be sent, so the
    /// prompt can say so; it used to sit there looking unresponsive with no way out.
    let onConfirm: () async throws -> Void
    let onSnooze: () async throws -> Void
    /// Close the prompt without answering. It comes back at the next launch.
    let onClose: () -> Void

    private enum Answer {
        case completed
        case notYet
    }

    /// The answer being sent. Both buttons are disabled while it is set.
    @State private var submitting: Answer?
    /// The last answer tapped, kept so Retry in the failure alert can repeat it.
    @State private var lastAnswer: Answer?
    @State private var showSendFailure = false

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
                    .background(Color.naarsInsetBackground)
                    .cornerRadius(Constants.Radius.sm)

                VStack(spacing: 12) {
                    PrimaryButton(
                        title: "common_confirm_completed".localized,
                        action: { submit(.completed) },
                        isLoading: submitting == .completed,
                        isDisabled: submitting != nil
                    )
                    SecondaryButton(
                        title: "common_not_yet".localized,
                        action: { submit(.notYet) },
                        isDisabled: submitting != nil
                    )
                    .overlay(alignment: .trailing) {
                        if submitting == .notYet {
                            ProgressView()
                                .padding(.trailing, Constants.Spacing.md)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("common_complete_request".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A full-screen cover cannot be swiped away, so it needs its own way out.
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_close".localized) {
                        onClose()
                    }
                    .disabled(submitting != nil)
                    .accessibilityIdentifier("completionPrompt.close")
                }
            }
            .interactiveDismissDisabled(true)
            .alert("completion_prompt_error_title".localized, isPresented: $showSendFailure) {
                Button("common_retry".localized) {
                    if let lastAnswer {
                        submit(lastAnswer)
                    }
                }
                Button("completion_prompt_later".localized, role: .cancel) {
                    onClose()
                }
            } message: {
                Text("completion_prompt_error_message".localized)
            }
        }
    }

    private func submit(_ answer: Answer) {
        guard submitting == nil else { return }
        submitting = answer
        lastAnswer = answer
        Task {
            do {
                switch answer {
                case .completed:
                    try await onConfirm()
                case .notYet:
                    try await onSnooze()
                }
            } catch {
                showSendFailure = true
            }
            submitting = nil
        }
    }
}
