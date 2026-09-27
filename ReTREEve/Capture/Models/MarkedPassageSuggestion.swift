//  MarkedPassageSuggestion.swift
//  What an automatic marked-region detector proposes — never what it decides.
//
//  A suggestion is always a proposal about EXISTING regions, identified by id
//  rather than by text. That keeps a detector honest: it can only point at text
//  the recognizer already read, so it cannot invent a passage, and the selection
//  UI can render its proposal using the boxes it already has on screen.

import Foundation
import CoreGraphics

/// How the reader appears to have marked the passage. Advisory only — it changes
/// wording in the UI, never behaviour.
enum MarkKind: String, Hashable, Sendable {
    case highlight
    case underline
    case circle
    case marginMark
    case unknown

    var describedAsPhrase: String {
        switch self {
        case .highlight:  "highlighted"
        case .underline:  "underlined"
        case .circle:     "circled"
        case .marginMark: "marked in the margin"
        case .unknown:    "marked"
        }
    }
}

/// Zero or more of these come back from a `MarkedPassageDetecting` implementation.
nonisolated struct MarkedPassageSuggestion: Identifiable, Hashable {
    let id: UUID

    /// The regions this suggestion covers, in no particular order —
    /// `PassageAssembler` re-establishes reading order when the text is built.
    let regionIDs: [RecognizedTextRegion.ID]

    /// How far across each line the mark actually ran, in page coordinates.
    ///
    /// A mark is rarely the width of a printed line. Underlining the tail of one
    /// line and the head of the next means those words, and a line-level id
    /// cannot say so — it can only say "all eleven words of this line". The span
    /// is what lets the passage come back as the phrase the reader marked.
    ///
    /// This does not weaken the rule that a detector cannot invent a passage: a
    /// span only ever narrows a region the detector already named, and the words
    /// it selects come from what the recognizer read at that position.
    ///
    /// A region with no entry means the whole line.
    let markedSpans: [RecognizedTextRegion.ID: ClosedRange<CGFloat>]

    /// 0…1 where the detector can report it, `nil` where it cannot.
    let confidence: Double?

    let markKind: MarkKind

    /// Which detector produced this, for diagnostics and for showing the reader
    /// what made the guess. Matches `MarkedPassageDetecting.identifier`.
    let detectorIdentifier: String

    init(id: UUID = UUID(),
         regionIDs: [RecognizedTextRegion.ID],
         markedSpans: [RecognizedTextRegion.ID: ClosedRange<CGFloat>] = [:],
         confidence: Double? = nil,
         markKind: MarkKind = .unknown,
         detectorIdentifier: String) {
        self.id = id
        self.regionIDs = regionIDs
        self.markedSpans = markedSpans
        self.confidence = confidence
        self.markKind = markKind
        self.detectorIdentifier = detectorIdentifier
    }
}
