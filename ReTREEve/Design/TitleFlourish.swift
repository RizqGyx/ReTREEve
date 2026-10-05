//  TitleFlourish.swift
//  The short gilt rule and sparkle beneath a screen's navigation title.
//
//  Shared by Insight Detail and Possible Matches, which the design gives the
//  same ornamented heading.

import SwiftUI

struct TitleFlourish: View {
    var body: some View {
        HStack(spacing: 8) {
            rule
            SparkleShape()
                .fill(Grimoire.accentMagic)
                .frame(width: 11, height: 11)
            rule
        }
        .accessibilityHidden(true)
    }

    private var rule: some View {
        Rectangle()
            .fill(Grimoire.accentMagic.opacity(0.5))
            .frame(width: 44, height: 1)
    }
}
