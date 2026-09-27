//  NoopMarkedPassageDetector.swift
//  The detector that ships today: it detects nothing, deliberately.
//
//  This is not a stub awaiting completion — it is the honest default. ReTREEve
//  does not yet claim to know which passage a reader marked, so it does not
//  guess. The reader selects, exactly as they always could.
//
//  Its real job is to keep the automatic-detection path exercised in production:
//  the selection screen already runs a detector, already handles an empty
//  result, and already has the confirm/adjust affordances a real detector will
//  need. Swapping in a working detector is a one-line change at the call site in
//  `CaptureFlowView`, not a rewrite.

import Foundation

struct NoopMarkedPassageDetector: MarkedPassageDetecting {
    let identifier = "noop"

    /// Available in the sense that it always runs and always succeeds.
    /// It simply never has anything to propose.
    let isAvailable = true

    func suggestMarkedPassages(on page: CapturedPage) async -> [MarkedPassageSuggestion] {
        []
    }
}
