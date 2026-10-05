//  PassageQuoteMark.swift
//  The gilt opening quote that marks text as a passage from a book.
//
//  One component so the selection card, Book Details and anything later all use
//  the same glyph, weight and colour.

import SwiftUI

struct PassageQuoteMark: View {
    var size: CGFloat = 20

    /// Scales with Dynamic Type so it stays in proportion to the passage beside it.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: "quote.opening")
            .font(.system(size: size * scale, weight: .bold))
            .foregroundStyle(Grimoire.accentMagic)
            .accessibilityHidden(true)
    }
}
