//
//  MessageSearchResultRow.swift
//  NaarsCars
//
//  Row displaying a message search result with highlighted match
//

import SwiftUI

/// Row displaying a message search result with highlighted match
struct MessageSearchResultRow: View {
    let result: MessageSearchResult
    let searchQuery: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "message.fill")
                .font(.naarsSubheadline)
                .foregroundColor(.naarsPrimary)
                .frame(width: 36, height: 36)
                .background(Color.naarsPrimary.opacity(0.12))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                // Conversation name
                Text(result.conversationTitle)
                    .font(.naarsSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Message snippet with highlighted match
                highlightedText(result.message.text, query: searchQuery)
                    .font(.naarsCaption)
                    .lineLimit(2)
                
                // Sender name + timestamp
                HStack(spacing: 4) {
                    if let senderName = result.message.sender?.name {
                        Text(senderName)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    Text("·")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    Text(result.message.createdAt.timeAgoString)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.right")
                .font(.naarsFootnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    /// Build an attributed text view with the matching query highlighted
    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty else {
            return Text(text).foregroundColor(.secondary)
        }
        
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()
        
        guard let range = lowercasedText.range(of: lowercasedQuery) else {
            return Text(text).foregroundColor(.secondary)
        }
        
        // Show a window around the match for context
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let snippetStart = max(0, matchStart - 20)
        let startIdx = text.index(text.startIndex, offsetBy: snippetStart)
        let endIdx = text.index(startIdx, offsetBy: min(text.distance(from: startIdx, to: text.endIndex), 100))
        let snippet = String(text[startIdx..<endIdx])
        
        let prefix = snippetStart > 0 ? "…" : ""
        let suffix = endIdx < text.endIndex ? "…" : ""
        
        // Build highlighted text
        let snippetLower = snippet.lowercased()
        guard let matchRange = snippetLower.range(of: lowercasedQuery) else {
            return Text(prefix + snippet + suffix).foregroundColor(.secondary)
        }
        
        let before = String(snippet[snippet.startIndex..<matchRange.lowerBound])
        let match = String(snippet[matchRange])
        let after = String(snippet[matchRange.upperBound..<snippet.endIndex])
        
        return Text(prefix)
            .foregroundColor(.secondary)
        + Text(before)
            .foregroundColor(.secondary)
        + Text(match)
            .foregroundColor(.naarsPrimary)
            .fontWeight(.semibold)
        + Text(after)
            .foregroundColor(.secondary)
        + Text(suffix)
            .foregroundColor(.secondary)
    }
}
