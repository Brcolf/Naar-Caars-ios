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
    let onPostQuestion: (String) async -> Void
    let isClaimed: Bool
    let onMessageParticipants: (() -> Void)?
    
    @State private var newQuestion: String = ""
    @State private var isPosting: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Questions & Answers")
                .font(.naarsTitle3)
            
            // Q&A List
            if qaItems.isEmpty {
                Text("No questions yet. Be the first to ask!")
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(qaItems) { qa in
                    VStack(alignment: .leading, spacing: 8) {
                        // Question
                        HStack(alignment: .top) {
                            if let asker = qa.asker {
                                AvatarView(imageUrl: asker.avatarUrl, name: asker.name, size: 32)
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
                            
                            Text(qa.createdAt.timeAgo)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Answer (if present)
                        if let answer = qa.answer {
                            HStack(alignment: .top) {
                                Image(systemName: "arrow.turn.down.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                
                                Text(answer)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 40)
                        }
                    }
                    .padding()
                    .background(Color.naarsCardBackground)
                    .cornerRadius(8)
                }
            }
            
            if isClaimed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This request has been claimed. Please message participants for follow-up questions.")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)

                    PrimaryButton(
                        title: "Message Participants",
                        action: {
                            onMessageParticipants?()
                        },
                        isDisabled: onMessageParticipants == nil
                    )
                }
            } else {
                // Post question form
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask a Question")
                        .font(.naarsHeadline)
                    
                    TextField("Type your question...", text: $newQuestion, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    
                    PrimaryButton(title: "Post Question", action: {
                        Task {
                            isPosting = true
                            await onPostQuestion(newQuestion)
                            newQuestion = ""
                            isPosting = false
                        }
                    }, isLoading: isPosting, isDisabled: newQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .cardStyle()
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
        onPostQuestion: { _ in },
        isClaimed: false,
        onMessageParticipants: nil
    )
    .padding()
}



