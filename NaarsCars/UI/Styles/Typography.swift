//
//  Typography.swift
//  NaarsCars
//
//  Text style definitions for consistent typography
//

import SwiftUI

/// Typography styles for consistent text appearance
/// Uses built-in text styles that automatically scale with Dynamic Type
extension Font {
    /// Large title style - for main headings
    static let naarsLargeTitle = Font.largeTitle.weight(.bold)
    
    /// Title style - for section headings
    static let naarsTitle = Font.title.weight(.semibold)
    
    /// Title 2 style - for subsection headings
    static let naarsTitle2 = Font.title2.weight(.semibold)
    
    /// Title 3 style - for card titles
    static let naarsTitle3 = Font.title3.weight(.semibold)
    
    /// Headline style - for emphasized text
    static let naarsHeadline = Font.headline
    
    /// Body style - for regular text
    static let naarsBody = Font.body
    
    /// Callout style - for secondary text
    static let naarsCallout = Font.callout
    
    /// Subheadline style - for smaller emphasized text
    static let naarsSubheadline = Font.subheadline
    
    /// Footnote style - for captions and metadata
    static let naarsFootnote = Font.footnote
    
    /// Caption style - for smallest text
    static let naarsCaption = Font.caption
}

