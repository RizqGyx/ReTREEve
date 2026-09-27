//  RecognizedTextRegion.swift
//  The app-level representation of "some text, and where it was found".
//
//  Deliberately free of VisionKit and Vision types. Any recognizer — today's
//  Vision one, a future custom pipeline, even a remote service — produces this
//  same shape, so the selection UI and any future detector never have to change
//  when the recognition backend does.

import Foundation
import CoreGraphics
import UIKit

/// One word, and where it sits on the page.
///
/// Kept because a mark rarely covers a whole printed line. A reader underlining
/// "Friedman menyimpulkan" at the end of a line means those two words, not the
/// eleven-word line that contains them, and a line-level box cannot express the
/// difference. These come from the SAME recognition pass as the line — Vision
/// can report the box for any range of what it read — so nothing is re-read and
/// no second OCR is involved.
nonisolated struct TextWord: Hashable, Sendable {
    let text: String
    /// PAGE NORMALIZED, exactly like `RecognizedTextRegion.boundingBox`.
    let boundingBox: CGRect
}

/// One recognized run of text with its position on the page.
nonisolated struct RecognizedTextRegion: Identifiable, Hashable {
    let id: UUID

    /// The recognized string, already trimmed. Never empty.
    let text: String

    /// PAGE NORMALIZED coordinates: origin top-left, x,y ∈ [0,1], y downward.
    /// See `PageGeometry` for the full contract — this is the app's canonical space.
    let boundingBox: CGRect

    /// 0…1 where the recognizer reports it, `nil` where it does not.
    let confidence: Double?

    /// Natural reading position, assigned by `PassageAssembler` at recognition
    /// time. Selecting regions out of order still yields a correctly ordered
    /// passage, because joining sorts on this rather than on tap order.
    let readingOrderIndex: Int

    /// The individual words, in reading order. Empty where the recognizer could
    /// not report them, in which case everything falls back to whole lines.
    let words: [TextWord]

    init(id: UUID = UUID(),
         text: String,
         boundingBox: CGRect,
         confidence: Double?,
         readingOrderIndex: Int,
         words: [TextWord] = []) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.readingOrderIndex = readingOrderIndex
        self.words = words
    }

    /// Recognizers report low confidence on blurred or skewed lines. Surfaced in
    /// the UI as a hint to check the text, never as a reason to hide a region.
    var isLowConfidence: Bool {
        guard let confidence else { return false }
        return confidence < 0.5
    }

    /// The words this line contributes to a passage, given the horizontal span a
    /// mark covered. `nil` means the whole line, which is what a tap means.
    ///
    /// A word counts as marked when the span covers at least
    /// `minimumWordCoverage` of it. Partial rather than total, because a reader
    /// stops an underline where the thought ends, not where the word does — the
    /// stroke under "positif," routinely stops a little short of the comma.
    ///
    /// Never returns an empty string: a span that lands between words falls back
    /// to the whole line rather than silently dropping it from the passage.
    func text(markedWithin span: ClosedRange<CGFloat>?) -> String {
        guard let span, !words.isEmpty else { return text }

        let kept = words.filter { word in
            let box = word.boundingBox
            guard box.width > 0 else { return false }
            let shared = min(box.maxX, span.upperBound) - max(box.minX, span.lowerBound)
            return shared / box.width >= Self.minimumWordCoverage
        }

        guard !kept.isEmpty else { return text }
        return kept.map(\.text).joined(separator: " ")
    }

    static let minimumWordCoverage: CGFloat = 0.5
}

/// A frozen page: the image, its coordinate space, and everything read from it.
///
/// The image and `pixelSize` are retained deliberately. A future marked-region
/// detector needs the original pixels plus the coordinate space its output must
/// be expressed in — discarding either would make spatial overlap with OCR
/// regions impossible, which is the whole point of the abstraction.
nonisolated struct CapturedPage {
    let id: UUID
    let image: UIImage

    /// Pixel dimensions in the ORIENTED space Vision reasoned about.
    /// `PageGeometry.orientedPixelSize(of:)` is the only thing that computes it.
    let pixelSize: CGSize

    let regions: [RecognizedTextRegion]
    let capturedAt: Date

    init(id: UUID = UUID(),
         image: UIImage,
         pixelSize: CGSize,
         regions: [RecognizedTextRegion],
         capturedAt: Date = .now) {
        self.id = id
        self.image = image
        self.pixelSize = pixelSize
        self.regions = regions
        self.capturedAt = capturedAt
    }

    var hasText: Bool { !regions.isEmpty }

    func region(with id: RecognizedTextRegion.ID) -> RecognizedTextRegion? {
        regions.first { $0.id == id }
    }
}
