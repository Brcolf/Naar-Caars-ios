//
//  PostTitleExtractor.swift
//  NaarsCars
//
//  Utility to extract post titles from message content
//

import Foundation

/// Utility to extract meaningful titles from post content
struct PostTitleExtractor {
    /// Extract a title from post content by finding the most important summary elements
    /// - Parameter content: The post content
    /// - Returns: A title extracted from the content (or a default if extraction fails)
    static func extractTitle(from content: String, maxLength: Int = 100) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If content is very short, use it as-is
        if trimmed.count <= maxLength {
            return trimmed.isEmpty ? "New Post" : trimmed
        }
        
        // Try to find the first sentence (ending with . ! or ?)
        if let sentenceEnd = trimmed.range(of: #"[.!?]\s"#, options: .regularExpression) {
            let firstSentence = String(trimmed[..<sentenceEnd.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !firstSentence.isEmpty && firstSentence.count <= maxLength {
                // Remove trailing punctuation
                return firstSentence.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            }
        }
        
        // Try to find the first line (ending with newline)
        if let newlineIndex = trimmed.firstIndex(of: "\n") {
            let firstLine = String(trimmed[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !firstLine.isEmpty && firstLine.count <= maxLength {
                return firstLine
            }
        }
        
        // Try to find important keywords (capitalized words or keywords)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
        var importantWords: [String] = []
        
        for word in words.prefix(10) { // Check first 10 words
            let cleaned = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            // Look for capitalized words or common keywords
            if cleaned.count > 3 && (cleaned.first?.isUppercase == true || 
                ["ride", "favor", "help", "need", "looking", "thank", "thanks", "awesome", "great"].contains(cleaned.lowercased())) {
                importantWords.append(cleaned)
            }
            if importantWords.count >= 5 {
                break
            }
        }
        
        if !importantWords.isEmpty {
            let extracted = importantWords.joined(separator: " ")
            if extracted.count <= maxLength {
                return extracted
            }
        }
        
        // Fallback: truncate the content
        let truncated = String(trimmed.prefix(maxLength - 3))
        return truncated.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}


