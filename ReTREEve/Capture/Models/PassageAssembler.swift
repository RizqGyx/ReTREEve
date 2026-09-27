//  PassageAssembler.swift
//  Turning scattered OCR fragments into one passage a reader would recognise.
//
//  Deliberately spatial, never structural. Nothing here assumes an OCR region is
//  a paragraph, a sentence, or even a complete line — book pages carry prose,
//  dialogue, verse, footnotes, running heads and multi-column layouts, and a
//  recognizer will happily split any of them mid-phrase. Ordering and joining
//  therefore work purely from geometry.

import Foundation
import CoreGraphics

/// What a recognizer produces before reading order has been worked out.
nonisolated struct RawTextRegion {
    let text: String
    /// PAGE NORMALIZED, origin top-left. See `PageGeometry`.
    let boundingBox: CGRect
    let confidence: Double?
    /// Per-word boxes where the recognizer could report them. Empty is fine and
    /// simply means passages from this line can only ever be whole lines.
    var words: [TextWord] = []
}

nonisolated enum PassageAssembler {

    /// Two fragments belong to the same printed line if they share this much of
    /// the shorter one's height.
    private static let sameLineThreshold: CGFloat = 0.5

    /// Fragments this similar in text and position are the same thing recognized twice.
    private static let duplicateOverlapThreshold: CGFloat = 0.75

    // MARK: - Reading order

    /// Groups fragments into printed lines, orders the lines top-to-bottom and
    /// each line left-to-right, and stamps the result with `readingOrderIndex`.
    ///
    /// Line banding rather than a plain y-sort matters because a single printed
    /// line often arrives as several fragments with slightly different y values;
    /// sorting those by y alone interleaves them with the line below.
    static func orderedRegions(from raw: [RawTextRegion]) -> [RecognizedTextRegion] {
        let cleaned = deduplicated(raw.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        guard !cleaned.isEmpty else { return [] }

        // Group into bands by vertical overlap, walking down the page.
        let byVerticalPosition = cleaned.sorted { $0.boundingBox.midY < $1.boundingBox.midY }
        var bands: [[RawTextRegion]] = []
        for fragment in byVerticalPosition {
            if let last = bands.last,
               let reference = last.first,
               PageGeometry.verticalOverlapRatio(fragment.boundingBox, reference.boundingBox) >= sameLineThreshold {
                bands[bands.count - 1].append(fragment)
            } else {
                bands.append([fragment])
            }
        }

        var ordered: [RecognizedTextRegion] = []
        var index = 0
        for band in bands {
            for fragment in band.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
                ordered.append(RecognizedTextRegion(
                    text: fragment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: fragment.boundingBox,
                    confidence: fragment.confidence,
                    readingOrderIndex: index,
                    words: fragment.words))
                index += 1
            }
        }
        return ordered
    }

    /// Drops fragments that repeat an earlier one at essentially the same place.
    private static func deduplicated(_ raw: [RawTextRegion]) -> [RawTextRegion] {
        var kept: [RawTextRegion] = []
        for candidate in raw {
            let candidateText = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isDuplicate = kept.contains { existing in
                existing.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == candidateText
                    && PageGeometry.intersectionOverUnion(existing.boundingBox, candidate.boundingBox) > duplicateOverlapThreshold
            }
            if !isDuplicate { kept.append(candidate) }
        }
        return kept
    }

    // MARK: - Joining

    /// Joins regions into one passage in reading order, regardless of the order
    /// the reader tapped them in.
    ///
    /// Handles the one typographic artefact that genuinely corrupts a scanned
    /// book passage: a word broken across a line with a trailing hyphen. Rejoined
    /// only when the next fragment starts lowercase, so "well-known" and
    /// "self-doubt" survive intact while "consist-" + "ently" is repaired.
    static func passage(from regions: [RecognizedTextRegion]) -> String {
        passage(from: regions, marked: [:])
    }

    /// The same join, but each line trimmed to the words a mark actually covered.
    ///
    /// `marked` carries the horizontal span of the mark over a line, in page
    /// coordinates. A line with no entry contributes in full — which is exactly
    /// what a tap means, since a tap says "this line" and carries no span.
    static func passage(from regions: [RecognizedTextRegion],
                        marked: [RecognizedTextRegion.ID: ClosedRange<CGFloat>]) -> String {
        let ordered = regions.sorted { $0.readingOrderIndex < $1.readingOrderIndex }
        var assembled = ""

        for region in ordered {
            let piece = region.text(markedWithin: marked[region.id])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }

            guard !assembled.isEmpty else { assembled = piece; continue }

            if assembled.hasSuffix("-"), let first = piece.first, first.isLowercase {
                assembled.removeLast()
                assembled += piece
            } else {
                assembled += " " + piece
            }
        }

        return normalizeWhitespace(assembled)
    }

    /// Collapses the runs of spaces and stray newlines OCR introduces.
    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "[\\s\\u{00A0}]+",
                                  with: " ",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
