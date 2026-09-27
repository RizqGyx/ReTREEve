//  CoreMLMarkedPassageDetector.swift
//  The real detector: the V3 segmentation model, translated into a proposal
//  about OCR regions.
//
//  ── WHAT THIS FILE IS AND IS NOT ───────────────────────────────────────────
//
//  `AnnotationDetector` answers "where are the pen strokes on this page".
//  It knows nothing about text. This file answers the question the app actually
//  asks — "WHICH LINES DID THE READER MARK" — by intersecting those strokes with
//  the regions the recognizer already read. It cannot invent a passage: a
//  suggestion can only ever name region ids that already exist on the page.
//
//  The rule from `MarkedPassageDetecting` still holds. Nothing here saves,
//  mutates or commits. It preselects, and the reader confirms.
//
//  ── WHY MATCHING IS PER MARK KIND ──────────────────────────────────────────
//
//  A highlight sits ON the words: its mask overlaps the text box, so coverage is
//  the right test, and it is measured against the MASK rather than the bounding
//  box because a stroke that stops mid-line should not claim the whole line.
//
//  An underline sits UNDER the words. Its box barely touches the text box at
//  all, so coverage would score it near zero and the passage would come back
//  empty. Underlines and squiggles are matched by horizontal overlap plus
//  vertical proximity below the line instead.
//
//  Getting this wrong is silent: the model is fine, the app just suggests
//  nothing. That is why the two paths are separated explicitly.

import Foundation
import UIKit
import OSLog

nonisolated struct CoreMLMarkedPassageDetector: MarkedPassageDetecting {

    let identifier = "coreml.segmentation"

    /// Above the 0.25 the metrics were computed at. One phantom highlight costs
    /// the reader more than one missed highlight: a miss leaves them selecting
    /// by hand, which is the screen they were on anyway, while a phantom asks
    /// them to notice and undo a wrong guess.
    let confidenceThreshold: Float

    /// How much of a text line a highlight mask must cover before that line is
    /// considered marked — but only ever applied to a line the mark actually
    /// sits on. See `sameLineThreshold` for why that pairing matters.
    let coverageThreshold: CGFloat

    /// How much of a printed line's height the mark must share before the two
    /// are considered to be on the same line at all.
    ///
    /// ── WHY THIS GATE EXISTS ───────────────────────────────────────────────
    ///
    /// Coverage alone is measured as a fraction of the TEXT LINE's area, which
    /// quietly punishes long lines: one highlighter stroke covering half of a
    /// wide line scores below the same stroke covering all of a short one. The
    /// symptom is unmistakable and was exactly what showed up on real pages —
    /// a marked paragraph came back as its LAST line only, because the last
    /// line of a paragraph is the short one.
    ///
    /// Vertical alignment is what coverage was standing in for: it is the thing
    /// that actually separates "this line" from "the line above". With it doing
    /// that job properly, the coverage floor drops to a sliver, and a partial
    /// highlight claims its whole line the way a reader would expect.
    let sameLineThreshold: CGFloat

    /// How much of the strip beneath a line must carry stroke before that line
    /// counts as underlined. Lower than `coverageThreshold` because a rule is
    /// thin by nature: it can only ever occupy a fraction of the strip's height,
    /// however emphatically it was drawn.
    let underlineThreshold: CGFloat

    init(confidenceThreshold: Float = 0.35,
         coverageThreshold: CGFloat = 0.12,
         sameLineThreshold: CGFloat = 0.4,
         underlineThreshold: CGFloat = 0.10) {
        self.confidenceThreshold = confidenceThreshold
        self.coverageThreshold = coverageThreshold
        self.sameLineThreshold = sameLineThreshold
        self.underlineThreshold = underlineThreshold
    }

    /// False when the compiled model is not in the bundle. Checked rather than
    /// assumed, so a build that failed to embed the .mlpackage degrades to
    /// manual selection instead of throwing inside the capture flow.
    var isAvailable: Bool {
        Bundle.main.url(forResource: "BookAnnotationDetector", withExtension: "mlmodelc") != nil
    }

    func suggestMarkedPassages(on page: CapturedPage) async -> [MarkedPassageSuggestion] {
        guard page.hasText, let detector = ModelBox.shared.detector() else { return [] }

        // The model must see an upright page: it letterboxes the raw CGImage,
        // which ignores the EXIF rotation a camera photo carries. Rendering at a
        // capped size also keeps a 12-megapixel photo from being copied at full
        // resolution for a model that will scale it to 832 regardless.
        guard let upright = Self.uprightImage(from: page.image, maxDimension: 1600) else { return [] }

        let annotations: [Annotation]
        do {
            annotations = try detector.detect(image: upright,
                                              confidenceThreshold: confidenceThreshold)
        } catch {
            // A detector that cannot run returns nothing. It never surfaces an
            // error into a flow that has a perfectly good manual path.
            Logger.detection.error("Annotation detection failed: \(error.localizedDescription)")
            return []
        }

        return suggestions(from: annotations,
                           imageSize: upright.size,
                           regions: page.regions)
    }

    // MARK: - Annotations → suggestions

    /// One suggestion per mark kind, each covering every line that kind touched.
    ///
    /// Per kind rather than per detection because a highlighter drawn across
    /// four lines commonly comes back as four separate detections, and four
    /// one-line suggestions would make the reader pick a quarter of their own
    /// passage. Kinds stay separate because a page can carry both a highlight
    /// and an unrelated underline, and merging those would propose a passage the
    /// reader never marked as one.
    func suggestions(from annotations: [Annotation],
                     imageSize: CGSize,
                     regions: [RecognizedTextRegion]) -> [MarkedPassageSuggestion] {

        guard imageSize.width > 0, imageSize.height > 0 else { return [] }

        var idsByKind: [MarkKind: Set<RecognizedTextRegion.ID>] = [:]
        var confidenceByKind: [MarkKind: Double] = [:]
        // How far across each line the marks of a kind ran, widened as further
        // detections claim the same line.
        var spansByKind: [MarkKind: [RecognizedTextRegion.ID: ClosedRange<CGFloat>]] = [:]

        for annotation in annotations {
            let kind = Self.markKind(for: annotation.kind)
            let assessed = Self.assess(annotation,
                                       imageSize: imageSize,
                                       regions: regions,
                                       coverageThreshold: coverageThreshold,
                                       sameLineThreshold: sameLineThreshold,
                                       underlineThreshold: underlineThreshold)
            let matched = assessed.filter(\.matched).map(\.region.id)

            guard !matched.isEmpty else { continue }

            idsByKind[kind, default: []].formUnion(matched)
            confidenceByKind[kind] = max(confidenceByKind[kind] ?? 0, Double(annotation.confidence))

            // The mark's horizontal reach over each line it claimed, clamped to
            // the line so a mark running into the margin cannot widen the span
            // past the text that exists there.
            let mark = Self.pageNormalized(annotation.boundingBox, in: imageSize)
            for row in assessed where row.matched {
                let box = row.region.boundingBox
                let lower = max(mark.minX, box.minX)
                let upper = min(mark.maxX, box.maxX)
                guard lower < upper else { continue }

                let span = lower...upper
                if let existing = spansByKind[kind]?[row.region.id] {
                    // Two strokes on one line are one phrase, so the span grows
                    // to cover both rather than the later one replacing the first.
                    spansByKind[kind, default: [:]][row.region.id] =
                        min(existing.lowerBound, lower)...max(existing.upperBound, upper)
                } else {
                    spansByKind[kind, default: [:]][row.region.id] = span
                }
            }
        }

        return idsByKind.compactMap { kind, ids in
            guard !ids.isEmpty else { return nil }
            // Reading order, so the proposal is inspectable and stable between
            // runs rather than following Set iteration order.
            let ordered = regions
                .filter { ids.contains($0.id) }
                .sorted { $0.readingOrderIndex < $1.readingOrderIndex }
                .map(\.id)

            return MarkedPassageSuggestion(regionIDs: ordered,
                                           markedSpans: spansByKind[kind] ?? [:],
                                           confidence: confidenceByKind[kind],
                                           markKind: kind,
                                           detectorIdentifier: identifier)
        }
        // How much text a mark claims, before how sure the model was about it.
        //
        // Confidence alone put a 0.82 detection sitting on a running header and
        // a page number ahead of a lower-scoring mark covering four lines of the
        // passage the reader actually underlined. The model's certainty that
        // SOMETHING is there says nothing about whether it is the thing the
        // reader meant, and a two-character page number almost never is.
        .sorted {
            ($0.regionIDs.count, $0.confidence ?? 0) > ($1.regionIDs.count, $1.confidence ?? 0)
        }
    }

    /// The model's four classes, expressed in the vocabulary the UI speaks.
    /// A drawn box around a passage is described to the reader as circled —
    /// `MarkKind` names the reader's intent, not the stroke's shape.
    static func markKind(for kind: Annotation.Kind) -> MarkKind {
        switch kind {
        case .highlight: .highlight
        case .underline: .underline
        case .squiggly:  .underline
        case .box:       .circle
        }
    }

    // MARK: - Matching one annotation against the page

    /// Detector space (pixels of the upright image) → page normalized, the one
    /// space every box in the app agrees on.
    static func pageNormalized(_ box: CGRect, in imageSize: CGSize) -> CGRect {
        CGRect(x: box.minX / imageSize.width,
               y: box.minY / imageSize.height,
               width: box.width / imageSize.width,
               height: box.height / imageSize.height)
    }

    /// Every region this annotation touches at all, with the number that decided
    /// it. The near misses are kept deliberately: a passage that comes back one
    /// line short is a threshold question, and a bare list of matches cannot
    /// answer it.
    ///
    /// ── WHY ON-THE-LINE WINS OUTRIGHT ──────────────────────────────────────
    ///
    /// The two rules are tried in order, not together, and the reason is what
    /// the model's masks actually look like on a real page. A `squiggly`
    /// detection does not come back as a thin stroke: its mask covers the
    /// UNDERLINED WORDS as well as the rule beneath them.
    ///
    /// With a mask that fat, asking every line "is there ink beneath you?"
    /// claims one line too many. The strip beneath line 10 reaches down into
    /// line 11's own text, the mask is set there, and line 10 is credited with
    /// an underline that belongs to the line below it. That is exactly the
    /// "it takes the marked line AND the one above it" symptom.
    ///
    /// So when the mask lies on top of any line's words, those lines ARE the
    /// answer and the strip is never consulted. The strip rule exists for the
    /// other shape of detection — a genuinely thin rule sitting in the gap,
    /// touching no text at all — where it is the only thing that can work.
    static func assess(_ annotation: Annotation,
                       imageSize: CGSize,
                       regions: [RecognizedTextRegion],
                       coverageThreshold: CGFloat,
                       sameLineThreshold: CGFloat,
                       underlineThreshold: CGFloat)
        -> [(region: RecognizedTextRegion, score: CGFloat, matched: Bool, rule: String)] {

        let mark = pageNormalized(annotation.boundingBox, in: imageSize)

        struct Candidate {
            let region: RecognizedTextRegion
            let coverage: CGFloat    // mask over the line's own words
            let beneath: CGFloat     // mask in the strip below the line
            let sharesLine: Bool
        }

        let candidates: [Candidate] = regions.compactMap { region in
            let box = region.boundingBox

            // GATE 1 — vertical plausibility, applied before anything else.
            //
            // Without this the candidate set was "every region sharing a
            // column", so a mark a third of the way down the page was assessed
            // against the footnote at the bottom and the running header at the
            // top. Every one of them scored a perfect horizontal overlap and was
            // then rejected on vertical grounds, which is why the diagnostic
            // showed a page of identical 1.00 rejects and told us nothing.
            guard isVerticallyPlausible(mark: mark, region: box) else { return nil }

            // GATE 2 — the mark must share a column with the line.
            guard PageGeometry.horizontalOverlapRatio(mark, box) >= minimumHorizontalOverlap
            else { return nil }

            return Candidate(
                region: region,
                coverage: maskCoverage(of: box, by: annotation, mark: mark),
                beneath: underlineCoverage(of: box, by: annotation, mark: mark),
                sharesLine: PageGeometry.verticalOverlapRatio(mark, box) >= sameLineThreshold)
        }

        // Does this mark lie ON any line's words? If so that settles it.
        let liesOnText = candidates.contains {
            $0.sharesLine && $0.coverage >= coverageThreshold
        }

        return candidates.map { candidate in
            if liesOnText {
                let matched = candidate.sharesLine && candidate.coverage >= coverageThreshold
                return (candidate.region, candidate.coverage, matched, matched ? "on" : "—")
            }
            let matched = candidate.beneath >= underlineThreshold
            return (candidate.region, candidate.beneath, matched, matched ? "under" : "—")
        }
    }

    /// Whether a mark could belong to this line at all: it either overlaps the
    /// line's own band, or lies in the strip immediately beneath it where an
    /// underline belongs. Anything further away is a different line's business.
    static func isVerticallyPlausible(mark: CGRect, region: CGRect) -> Bool {
        guard region.height > 0 else { return false }
        if PageGeometry.verticalOverlapRatio(mark, region) > 0 { return true }
        return mark.maxY > region.maxY && mark.minY <= region.maxY + region.height * 1.2
    }

    /// How much of a text region falls under the annotation's actual mask, 0…1.
    ///
    /// Sampled rather than integrated: the mask is a coarse 208-per-input-side
    /// grid, so a fixed sample lattice over the text box is as accurate as the
    /// data underneath it and costs a few hundred lookups per line.
    static func maskCoverage(of region: CGRect, by annotation: Annotation, mark: CGRect) -> CGFloat {
        guard annotation.maskWidth > 0, annotation.maskHeight > 0,
              !annotation.mask.isEmpty else {
            // No usable mask: fall back to the box, which is what the model
            // would have given us anyway.
            return PageGeometry.coverage(of: region, by: mark)
        }
        guard !region.intersection(mark).isNull, !region.intersection(mark).isEmpty else { return 0 }

        let columns = 24
        let rows = 6
        var hits = 0

        for row in 0..<rows {
            let v = (CGFloat(row) + 0.5) / CGFloat(rows)
            let y = region.minY + v * region.height
            for column in 0..<columns {
                let u = (CGFloat(column) + 0.5) / CGFloat(columns)
                let x = region.minX + u * region.width
                guard mark.contains(CGPoint(x: x, y: y)) else { continue }

                let mx = Int(((x - mark.minX) / mark.width) * CGFloat(annotation.maskWidth))
                let my = Int(((y - mark.minY) / mark.height) * CGFloat(annotation.maskHeight))
                let cx = min(annotation.maskWidth - 1, max(0, mx))
                let cy = min(annotation.maskHeight - 1, max(0, my))
                if annotation.mask[cy * annotation.maskWidth + cx] { hits += 1 }
            }
        }
        return CGFloat(hits) / CGFloat(columns * rows)
    }

    /// Mask coverage of the strip immediately beneath a line — where a rule or a
    /// squiggle actually lives.
    ///
    /// This replaced a test on the mark box's edges, which could not survive a
    /// real detection box. Those come back two or three line-heights tall,
    /// because the model encloses the underlined words along with the rule and
    /// often several underlined lines at once. Any single edge of such a box —
    /// centre, bottom, either — lands near exactly ONE of the lines it covers,
    /// so the passage came back as one line out of three.
    ///
    /// The mask does not have that problem: it carries the stroke itself. Asking
    /// each line whether there is ink under it lets one tall detection claim
    /// every line it genuinely marks, and refuse the ones it merely spans.
    static func underlineCoverage(of region: CGRect,
                                  by annotation: Annotation,
                                  mark: CGRect) -> CGFloat {
        guard region.height > 0 else { return 0 }
        let strip = CGRect(x: region.minX,
                           y: region.maxY,
                           width: region.width,
                           height: region.height * 0.7)
        return maskCoverage(of: strip, by: annotation, mark: mark)
    }

    /// Shared by the candidate gate and the underline test, so a mark cannot
    /// pass one and fail the other on the same measurement.
    static let minimumHorizontalOverlap: CGFloat = 0.35

    // MARK: - Image preparation

    /// A `.up` oriented copy, long side capped, drawn at scale 1 so points and
    /// pixels coincide and the returned boxes need no second conversion.
    static func uprightImage(from image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let oriented = PageGeometry.orientedPixelSize(of: image)
        guard oriented.width > 0, oriented.height > 0 else { return nil }

        let scale = min(1, maxDimension / max(oriented.width, oriented.height))
        let target = CGSize(width: (oriented.width * scale).rounded(),
                            height: (oriented.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        // Standard range, i.e. 8-bit sRGB. A photo picked from the library is
        // commonly Display P3, and letting that through would hand the model
        // colours the training set never contained — a wide-gamut yellow
        // highlighter is not the yellow this model learned.
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // `draw(in:)` applies imageOrientation, which is exactly the rotation
            // the raw CGImage the model would otherwise receive is missing.
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Model lifetime

/// Holds the loaded model for the life of the process.
///
/// Loading a 5.5 MB Core ML model costs a couple of hundred milliseconds, and
/// the capture flow can run several pages in a row. A failed load is remembered
/// too: a missing or corrupt model should be one log line, not one per page.
private final class ModelBox: @unchecked Sendable {
    static let shared = ModelBox()

    private let lock = NSLock()
    private var loaded: AnnotationDetector?
    private var loadFailed = false

    func detector() -> AnnotationDetector? {
        lock.lock()
        defer { lock.unlock() }

        if let loaded { return loaded }
        if loadFailed { return nil }

        do {
            let detector = try AnnotationDetector()
            loaded = detector
            return detector
        } catch {
            loadFailed = true
            Logger.detection.error("Could not load BookAnnotationDetector: \(error.localizedDescription)")
            return nil
        }
    }
}

extension Logger {
    /// `nonisolated`: detection and capture both log from off the main actor.
    nonisolated static let detection = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReTREEve",
                                  category: "detection")
}
