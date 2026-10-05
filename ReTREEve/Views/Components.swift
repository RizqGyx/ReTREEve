//  Components.swift

import SwiftUI

struct SampleTag: View {
    var body: some View {
        Text("Sample")
            .font(.grimoire(.caption2, .emphasized))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Grimoire.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Grimoire.secondarySoft, in: Capsule())
            .accessibilityLabel("Sample paraphrase, not a quotation")
    }
}

