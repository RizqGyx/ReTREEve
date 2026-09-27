//  MarkedPassageDetecting.swift
//  The extension point for automatic marked-passage detection.
//
//  ── THE CONTRACT ───────────────────────────────────────────────────────────
//
//    INPUT   a CapturedPage: the original image, its pixel coordinate space,
//            and the OCR regions already read from it.
//    OUTPUT  zero or more suggestions, each naming existing region ids.
//
//  ── THE RULE ───────────────────────────────────────────────────────────────
//
//    AI SUGGESTS. HUMAN CONFIRMS.
//
//  A detector may never save anything, may never mutate the page, and may never
//  be the only path to a passage. `PassageSelectionView` preselects a
//  suggestion and says where it came from; the reader can accept it, add to it,
//  remove from it, or clear it and select by hand. When a detector returns
//  nothing — which is exactly what ships today — the screen is simply the manual
//  selection screen, with no degraded state and no error.
//
//  Because detection consumes `CapturedPage` and emits region ids, a future
//  implementation slots in without touching the scanner, the selection UI, the
//  review screen, the editor, or the save pipeline.

import Foundation

protocol MarkedPassageDetecting: Sendable {
    /// Stable identifier recorded on every suggestion, e.g. "noop",
    /// "highlight.color", "coreml.segmentation".
    var identifier: String { get }

    /// Whether this detector can run at all right now — missing model asset,
    /// unsupported hardware, feature switched off. A detector that cannot run
    /// must report `false` rather than throwing or returning noise.
    var isAvailable: Bool { get }

    /// Proposals about which existing regions the reader appears to have marked.
    ///
    /// Must not throw and must not block the UI indefinitely: returning `[]` is
    /// always a valid answer and always degrades to manual selection.
    func suggestMarkedPassages(on page: CapturedPage) async -> [MarkedPassageSuggestion]
}
