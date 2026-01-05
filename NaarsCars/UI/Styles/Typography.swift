//
//  Typography.swift
//  NaarsCars
//
//  Text style definitions for consistent typography
//

import SwiftUI

/// Typography styles for consistent text appearance
extension Font {
    /// Large title style - for main headings
    static let naarsLargeTitle = Font.system(size: 34, weight: .bold, design: .default)
    
    /// Title style - for section headings
    static let naarsTitle = Font.system(size: 28, weight: .semibold, design: .default)
    
    /// Title 2 style - for subsection headings
    static let naarsTitle2 = Font.system(size: 22, weight: .semibold, design: .default)
    
    /// Title 3 style - for card titles
    static let naarsTitle3 = Font.system(size: 20, weight: .semibold, design: .default)
    
    /// Headline style - for emphasized text
    static let naarsHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    
    /// Body style - for regular text
    static let naarsBody = Font.system(size: 17, weight: .regular, design: .default)
    
    /// Callout style - for secondary text
    static let naarsCallout = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Subheadline style - for smaller emphasized text
    static let naarsSubheadline = Font.system(size: 15, weight: .regular, design: .default)
    
    /// Footnote style - for captions and metadata
    static let naarsFootnote = Font.system(size: 13, weight: .regular, design: .default)
    
    /// Caption style - for smallest text
    static let naarsCaption = Font.system(size: 12, weight: .regular, design: .default)
}

