import Foundation

struct PromptQueue {
    private(set) var items: [PromptItem] = []

    var count: Int { items.count }

    mutating func enqueue(_ prompt: PromptItem) {
        guard !items.contains(where: { $0.id == prompt.id }) else { return }
        items.append(prompt)
        items.sort { $0.sortDate < $1.sortDate }
    }

    mutating func dequeue() -> PromptItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }
}
