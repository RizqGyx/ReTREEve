//  AcornSavedFeedback.swift
//  What a save feels like.
//
//  A full success screen would be a fourth step in a flow the reader just
//  finished, asking them to dismiss something in order to be done. This is the
//  lighter reading of the same moment: the capture closes, Home is already
//  there, and an acorn lands on it.
//
//  ── WHY IT SETTLES DOWNWARD ────────────────────────────────────────────────
//
//  The acorn pops, then drifts DOWN and fades rather than floating away. The
//  tree is beneath it on Home, so the gesture reads as the acorn joining the
//  tree — the same thing the stat above it has just incremented. Drifting
//  upward would read as something leaving.

import SwiftUI

struct AcornSavedFeedback: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var popped = false
    @State private var settled = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // A bloom behind the acorn so it reads as arriving with light
                // rather than being pasted onto the page.
                Circle()
                    .fill(Grimoire.accentMagicSoft)
                    .frame(width: 128, height: 128)
                    .blur(radius: 22)
                    .opacity(popped ? 0.9 : 0)

                Image("Acorn")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .scaleEffect(popped ? 1 : 0.5)
                    .opacity(popped ? 1 : 0)

                MagicSparkle(size: 16, delay: 0.05)
                    .offset(x: 44, y: -36)
                MagicSparkle(size: 11, opacity: 0.8, delay: 0.25)
                    .offset(x: -46, y: -14)
                MagicSparkle(size: 9, opacity: 0.7, delay: 0.45)
                    .offset(x: 34, y: 38)
            }
            .frame(height: 128)
            .offset(y: settled ? 26 : 0)

            Text("Insight saved to your grimoire")
                .font(.grimoire(.subhead))
                .foregroundStyle(Grimoire.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Grimoire.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Grimoire.border, lineWidth: 1))
                .shadow(color: Grimoire.textPrimary.opacity(0.08), radius: 10, y: 4)
                .opacity(popped ? 1 : 0)
        }
        .onAppear(perform: play)
        // Announced as one phrase. The acorn is decoration; the sentence is the
        // whole message, and VoiceOver should interrupt with it rather than
        // waiting behind whatever is being read on Home.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Insight saved to your grimoire")
        .accessibilityAddTraits(.isStaticText)
    }

    private func play() {
        guard !reduceMotion else {
            popped = true
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { popped = true }
        withAnimation(.easeInOut(duration: 1.1).delay(0.45)) { settled = true }
    }
}
