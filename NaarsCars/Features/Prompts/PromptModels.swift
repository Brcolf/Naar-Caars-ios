import Foundation

struct CompletionPrompt: Identifiable, Equatable {
    let id: UUID
    let reminderId: UUID
    let requestType: RequestType
    let requestId: UUID
    let requestTitle: String
    let dueAt: Date
    
    var sortDate: Date {
        dueAt
    }
}

struct ReviewPrompt: Identifiable, Equatable {
    let id: UUID
    let requestType: RequestType
    let requestId: UUID
    let requestTitle: String
    let fulfillerId: UUID
    let fulfillerName: String
    let createdAt: Date
    
    var sortDate: Date {
        createdAt
    }
}

enum PromptItem: Identifiable, Equatable {
    case completion(CompletionPrompt)
    case review(ReviewPrompt)

    var id: UUID {
        switch self {
        case .completion(let prompt): return prompt.id
        case .review(let prompt): return prompt.id
        }
    }

    var sortDate: Date {
        switch self {
        case .completion(let prompt): return prompt.dueAt
        case .review(let prompt): return prompt.createdAt
        }
    }
}
