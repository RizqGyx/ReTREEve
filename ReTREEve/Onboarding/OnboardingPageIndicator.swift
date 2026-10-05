//  OnboardingPageIndicator.swift
//  Five dots, the current one stretched into a capsule.
//
//  Custom rather than the system page dots because `.page` style draws white on
//  a translucent pill, which disappears against parchment. This also lets the
//  active dot grow rather than only brighten, which survives greyscale and
//  colour-blindness.

import SwiftUI

struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Grimoire.primary : Grimoire.textDisabled)
                    .frame(width: index == current ? 20 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
                   value: current)
        // One element for VoiceOver: five separate dots would be five stops on
        // the way to the button, saying nothing each time.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
