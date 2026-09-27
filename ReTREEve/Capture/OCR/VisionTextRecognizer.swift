//  VisionTextRecognizer.swift
//  OCR over a frozen page, using Vision's modern Swift request API.
//
//  ── WHY VISION AND NOT DataScannerViewController's LIVE TEXT ────────────────
//
//  `DataScannerViewController` recognises text live, but its `RecognizedItem`
//  bounds are expressed in the SCANNER VIEW's coordinate space and describe a
//  frame that is moving under the reader's hands. Neither survives the freeze:
//  the moment the page is captured, those coordinates refer to a preview that no
//  longer exists, and they cannot be related to the pixels of the captured photo.
//
//  Since a future marked-region detector must compare its output against OCR
//  boxes IN THE IMAGE IT ANALYSED, the authoritative read has to happen on the
//  still image. So VisionKit is used for what it is best at — acquisition, with
//  a guided viewfinder that shows the reader their text is legible — and Vision
//  does the recognition that the rest of the pipeline depends on.
//
//  Vision reports boxes in NORMALIZED BOTTOM-LEFT coordinates. This file is the
//  ONLY place that fact is true; `toImageCoordinates(_:origin:.upperLeft)`
//  converts to the app's top-left space before anything escapes.

import Foundation
import UIKit
import Vision

struct VisionTextRecognizer: TextRecognizing {

    /// `.accurate` over `.fast`: a page is captured once and read once, and book
    /// typography with tight leading punishes the fast path.
    private let recognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate

    /// Vision's dictionary correction repairs the character confusions typical of
    /// printed text (rn→m, l→1). It occasionally "corrects" an unusual proper
    /// noun, which is one reason the reader gets a review step before saving.
    private let usesLanguageCorrection = true

    nonisolated func recognizePage(in image: UIImage) async throws -> CapturedPage {
        guard let cgImage = image.cgImage else {
            throw TextRecognitionError.unreadableImage
        }

        let orientation = PageGeometry.cgOrientation(from: image.imageOrientation)
        let pixelSize = PageGeometry.orientedPixelSize(of: image)
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            throw TextRecognitionError.unreadableImage
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = usesLanguageCorrection

        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: cgImage, orientation: orientation)
        } catch {
            throw TextRecognitionError.failed(error.localizedDescription)
        }

        let raw: [RawTextRegion] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            // ── THE ONE COORDINATE CONVERSION IN THE PIPELINE ──
            // Vision normalized (bottom-left) → image pixels (top-left) → page
            // normalized (top-left). Done against real pixel dimensions rather
            // than a unit rectangle so the intermediate value is inspectable.
            let pixelRect = observation.boundingBox.toImageCoordinates(pixelSize, origin: .upperLeft)
            let pageRect = CGRect(x: pixelRect.minX / pixelSize.width,
                                  y: pixelRect.minY / pixelSize.height,
                                  width: pixelRect.width / pixelSize.width,
                                  height: pixelRect.height / pixelSize.height)

            return RawTextRegion(text: text,
                                 boundingBox: pageRect,
                                 confidence: Double(candidate.confidence),
                                 words: Self.words(in: candidate, pixelSize: pixelSize))
        }

        let regions = PassageAssembler.orderedRegions(from: raw)
        guard !regions.isEmpty else { throw TextRecognitionError.noTextFound }

        return CapturedPage(image: image, pixelSize: pixelSize, regions: regions)
    }

    /// Per-word boxes, from the SAME recognition Vision already performed.
    ///
    /// `RecognizedText` can report the box for any range of the string it read,
    /// so asking it once per word costs a lookup rather than a second OCR pass.
    /// Re-recognising a cropped image instead would be strictly worse: the crop
    /// loses the sentence around it, and language correction then has to guess
    /// from a fragment.
    ///
    /// A word whose box cannot be resolved is skipped rather than faked. If that
    /// leaves the list empty the caller falls back to whole lines, which is the
    /// behaviour that existed before words were tracked at all.
    private nonisolated static func words(in candidate: RecognizedText,
                                          pixelSize: CGSize) -> [TextWord] {
        let string = candidate.string
        var result: [TextWord] = []

        var index = string.startIndex
        while index < string.endIndex {
            while index < string.endIndex, string[index].isWhitespace {
                index = string.index(after: index)
            }
            guard index < string.endIndex else { break }
            let start = index
            while index < string.endIndex, !string[index].isWhitespace {
                index = string.index(after: index)
            }
            let range = start..<index

            let piece = String(string[range])
            guard !piece.isEmpty else { continue }
            guard let region = candidate.boundingBox(for: range) else { continue }

            let pixelRect = region.boundingBox.toImageCoordinates(pixelSize, origin: .upperLeft)
            result.append(TextWord(
                text: piece,
                boundingBox: CGRect(x: pixelRect.minX / pixelSize.width,
                                    y: pixelRect.minY / pixelSize.height,
                                    width: pixelRect.width / pixelSize.width,
                                    height: pixelRect.height / pixelSize.height)))
        }
        return result
    }
}
