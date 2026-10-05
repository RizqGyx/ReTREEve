//  OnboardingPage.swift
//  What the five pages say, as data.
//
//  Copy and visual kind live here so `OnboardingPageView` can be written once
//  and used five times. Five hand-built screens would drift apart in spacing the
//  moment one of them was adjusted.

import Foundation

enum OnboardingVisual {
    case welcome
    case save
    case findAgain
    case grow
    case ready
}

struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let body: String
    let visual: OnboardingVisual
    let buttonTitle: String

    /// The last page is the one that finishes onboarding rather than advancing.
    var isFinal: Bool { id == OnboardingPage.all.count - 1 }
}

extension OnboardingPage {
    /// Four explanations and a send-off, worded as in the Sketch file.
    ///
    /// Nothing here mentions Reconnect, tags or favourites: they are not part of
    /// the product. Nothing mentions cameras needing permission either — the
    /// reader is told what capture is for, and asked for the camera only when
    /// they actually open it.
    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Welcome to\nReTREEve: Grimoire",
            body: "Save meaningful ideas from your physical books, and let them grow in your personal grimoire.",
            visual: .welcome,
            buttonTitle: "Start"),

        OnboardingPage(
            id: 1,
            title: "Save Insight",
            body: "Capture meaningful passages from physical books quickly with your camera.",
            visual: .save,
            buttonTitle: "Next"),

        OnboardingPage(
            id: 2,
            title: "Find Again",
            body: "Save parts of the book that are meaningful to you. Look up the insights you've saved, even if you only have a vague recollection of them.",
            visual: .findAgain,
            buttonTitle: "Next"),

        OnboardingPage(
            id: 3,
            title: "Grow Through Reading",
            body: "Your saved insights become part of your growing grimoire — a more thoughtful, connected you.",
            visual: .grow,
            buttonTitle: "Next"),

        OnboardingPage(
            id: 4,
            title: "Let's grow your grimoire.",
            body: "Every insight you save will make your tree grow and become stronger.",
            visual: .ready,
            buttonTitle: "Let's Start")
    ]
}
