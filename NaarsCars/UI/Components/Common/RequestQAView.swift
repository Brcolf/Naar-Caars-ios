//
//  RequestQAView.swift
//  NaarsCars
//
//  Q&A section component for ride and favor requests
//

import SwiftUI

/// Q&A section component for displaying and posting questions/answers
struct RequestQAView: View {
    let qaItems: [RequestQA]
    let requestId: UUID
    let requestType: String
    /// Posts the question. Returns `true` once it is saved; the field is cleared only then, so a
    /// failed post (offline, questions closed) keeps what the person typed.
    let onPostQuestion: (String) async -> Bool
    let isClaimed: Bool
    let onMessageParticipants: (() -> Void)?
    /// True while "Message Participants" is finding or creating the thread: the button shows
    /// progress and ignores taps (two quick taps could create two threads).
    var isOpeningConversation: Bool = false
    /// The signed-in user, to tell their own questions (Delete) from other people's (Report).
    /// nil for guests.
    var currentUserId: UUID? = nil
    /// Report someone else's question. Questions are user-generated content shown to every
    /// member and to guests, so each one needs a report path. nil hides the control.
    var onReportQuestion: ((RequestQA) -> Void)? = nil
    /// Delete the viewer's own question; returns true once it is gone. nil hides the control.
    var onDeleteQuestion: ((RequestQA) async -> Bool)? = nil
    /// Questions reported from this screen; they show "Reported" in place of the flag.
    var reportedQuestionIds: Set<UUID> = []

    @State private var newQuestion: String = ""
    @State private var isPosting: Bool = false
    @State private var questionPendingDelete: RequestQA?
    @State private var deletingQuestionId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("qa_section_title".localized)
                .font(.naarsTitle3)
                .accessibilityAddTraits(.isHeader)

            // Q&A List
            if qaItems.isEmpty {
                // Once a request is claimed nobody can ask, so "be the first to ask" would
                // contradict the note below it.
                if !isClaimed {
                    Text("qa_empty_message".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .padding()
                }
            } else {
                ForEach(qaItems) { qa in
                    VStack(alignment: .leading, spacing: 8) {
                        // Question
                        HStack(alignment: .top) {
                            if let asker = qa.asker {
                                // A link, so the asker's profile (and Block there) is one tap away.
                                // The label is padded out to a 44 pt target and the link pulled
                                // back in by the same amount, so the 32 pt avatar keeps its place.
                                NavigationLink(destination: PublicProfileView(userId: asker.id)) {
                                    AvatarView(
                                        imageUrl: asker.avatarUrl,
                                        name: asker.name,
                                        size: 32,
                                        userId: asker.id
                                    )
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .padding(-6)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if let asker = qa.asker {
                                    Text(asker.name)
                                        .font(.naarsSubheadline)
                                        .fontWeight(.semibold)
                                }

                                Text(qa.question)
                                    .font(.naarsBody)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 0) {
                                Text(qa.createdAt.timeAgo)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)

                                questionActions(for: qa)
                            }
                        }
                        
                        // Answer (if present)
                        if let answer = qa.answer {
                            HStack(alignment: .top) {
                                Image(systemName: "arrow.turn.down.right")
                                    .foregroundColor(.secondary)
                                    .font(.naarsCaption)
                                
                                Text(answer)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 40)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.naarsInsetBackground)
                    .cornerRadius(Constants.Radius.sm)
                }
            }
            
            if isClaimed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("qa_claimed_message".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)

                    // Outlined: the claim / complete action below is this screen's one filled
                    // button, and this used to be a second one beside it.
                    SecondaryButton(
                        title: "qa_message_participants".localized,
                        action: {
                            onMessageParticipants?()
                        },
                        isDisabled: onMessageParticipants == nil || isOpeningConversation
                    )
                    .overlay(alignment: .trailing) {
                        if isOpeningConversation {
                            ProgressView()
                                .padding(.trailing, Constants.Spacing.md)
                        }
                    }
                }
            } else {
                // Post question form
                VStack(alignment: .leading, spacing: 8) {
                    Text("qa_ask_question_title".localized)
                        .font(.naarsHeadline)
                    
                    TextField("qa_question_placeholder".localized, text: $newQuestion, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.naarsBody)
                        .lineLimit(2...4)
                        .padding(Constants.Spacing.ms)
                        .background(Color.naarsInsetBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.sm, style: .continuous))
                    
                    PrimaryButton(title: "qa_post_question_button".localized, action: {
                        guard !isPosting else { return }
                        isPosting = true
                        Task {
                            defer { isPosting = false }
                            if await onPostQuestion(newQuestion) {
                                newQuestion = ""
                            }
                        }
                    }, isLoading: isPosting, isDisabled: newQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .cardStyle()
        .alert(
            "qa_delete_question_title".localized,
            isPresented: Binding(
                get: { questionPendingDelete != nil },
                set: { if !$0 { questionPendingDelete = nil } }
            ),
            presenting: questionPendingDelete
        ) { qa in
            Button("common_cancel".localized, role: .cancel) {}
            Button("common_delete".localized, role: .destructive) {
                deleteQuestion(qa)
            }
        } message: { _ in
            Text("qa_delete_question_confirmation".localized)
        }
    }

    /// Report (someone else's question) or Delete (the viewer's own), under the timestamp.
    @ViewBuilder
    private func questionActions(for qa: RequestQA) -> some View {
        let isOwnQuestion = currentUserId != nil && qa.userId == currentUserId
        if isOwnQuestion {
            if onDeleteQuestion != nil {
                Button {
                    questionPendingDelete = qa
                } label: {
                    Image(systemName: "trash")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(deletingQuestionId == qa.id)
                .accessibilityLabel("qa_delete_question_accessibility".localized)
            }
        } else if let onReportQuestion {
            if reportedQuestionIds.contains(qa.id) {
                Label("townhall_reported".localized, systemImage: "flag.fill")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .frame(minHeight: 44)
            } else {
                Button {
                    onReportQuestion(qa)
                } label: {
                    Image(systemName: "flag")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("qa_report_question_accessibility".localized)
            }
        }
    }

    private func deleteQuestion(_ qa: RequestQA) {
        guard deletingQuestionId == nil, let onDeleteQuestion else { return }
        deletingQuestionId = qa.id
        Task {
            _ = await onDeleteQuestion(qa)
            deletingQuestionId = nil
        }
    }
}

#Preview {
    RequestQAView(
        qaItems: [
            RequestQA(
                rideId: UUID(),
                favorId: nil,
                userId: UUID(),
                question: "What time do you need to arrive?",
                answer: "By 2 PM would be great!",
                createdAt: Date().addingTimeInterval(-3600),
                asker: nil
            )
        ],
        requestId: UUID(),
        requestType: "ride",
        onPostQuestion: { _ in true },
        isClaimed: false,
        onMessageParticipants: nil
    )
    .padding()
}



