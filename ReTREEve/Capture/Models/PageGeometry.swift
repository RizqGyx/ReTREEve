//  PageGeometry.swift
//
//  THE SINGLE AUTHORITY FOR CAPTURE COORDINATE MATH.
//  No other file in the capture pipeline may convert between coordinate spaces.
//  A future marked-region detector will compare its own masks against OCR boxes,
//  and that comparison is only sound if every box in the app agrees on one
//  contract. That contract is defined here.
//
//  ── THE THREE SPACES ────────────────────────────────────────────────────────
//
//  1. VISION NORMALIZED  — what `RecognizeTextRequest` hands back.
//     Origin BOTTOM-LEFT. x,y ∈ [0,1]. y grows UPWARD.
//     Relative to the image *after* the orientation passed to `perform` is applied.
//     This space exists only inside VisionTextRecognizer and never escapes it.
//
//  2. PAGE NORMALIZED    — the app's canonical space. `RecognizedTextRegion.boundingBox`.
//     Origin TOP-LEFT. x,y ∈ [0,1]. y grows DOWNWARD (UIKit/SwiftUI convention).
//     Resolution independent, so a region stays valid if the image is
//     re-encoded, downscaled, or re-read at a different scale.
//     >>> Everything outside the recognizer speaks this space. <<<
//
//  3. DISPLAY            — points inside a SwiftUI container.
//     Origin TOP-LEFT of the container, NOT of the image. Because the page is
//     drawn with `.scaledToFit()`, the image is letterboxed inside the container
//     and its frame must be computed before any box can be placed.
//
//  ── THE CONVERSION ─────────────────────────────────────────────────────────
//
//     Vision normalized ──(VisionTextRecognizer, once)──▶ Page normalized
//     Page normalized   ──(displayRect, per layout pass)─▶ Display
//     Display           ──(pageRect, drag selection)─────▶ Page normalized
//
//  Orientation is resolved at recognition time by handing Vision the image's
//  CGImagePropertyOrientation, so page-normalized boxes are already upright and
//  no view ever has to think about EXIF rotation.

import CoreGraphics
import UIKit

nonisolated enum PageGeometry {

    // MARK: - Orientation

    /// Vision works on the raw `CGImage`, which ignores the EXIF rotation that
    /// `UIImage` carries separately. Passing this to the request is what keeps
    /// a page photographed sideways from producing sideways boxes.
    static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:            .up
        case .down:          .down
        case .left:          .left
        case .right:         .right
        case .upMirrored:    .upMirrored
        case .downMirrored:  .downMirrored
        case .leftMirrored:  .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default:    .up
        }
    }

    /// The pixel dimensions Vision actually reasons about, i.e. after the
    /// orientation above has been applied. For a `.left`/`.right` oriented image
    /// the CGImage is stored rotated, so width and height swap.
    static func orientedPixelSize(of image: UIImage) -> CGSize {
        guard let cg = image.cgImage else {
            return CGSize(width: image.size.width * image.scale,
                          height: image.size.height * image.scale)
        }
        let raw = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: raw.height, height: raw.width)
        default:
            return raw
        }
    }

    // MARK: - Page normalized → Display

    /// Where the letterboxed image actually sits inside a `.scaledToFit()` container.
    /// Every display conversion goes through this; nothing assumes the image
    /// fills its container.
    static func fittedImageFrame(container: CGSize, pixelSize: CGSize) -> CGRect {
        guard container.width > 0, container.height > 0,
              pixelSize.width > 0, pixelSize.height > 0 else { return .zero }

        let scale = min(container.width / pixelSize.width,
                        container.height / pixelSize.height)
        let drawn = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        return CGRect(x: (container.width - drawn.width) / 2,
                      y: (container.height - drawn.height) / 2,
                      width: drawn.width,
                      height: drawn.height)
    }

    /// Page-normalized rect → a rect in container points.
    static func displayRect(for normalized: CGRect,
                            container: CGSize,
                            pixelSize: CGSize) -> CGRect {
        let frame = fittedImageFrame(container: container, pixelSize: pixelSize)
        guard !frame.isEmpty else { return .zero }
        return CGRect(x: frame.minX + normalized.minX * frame.width,
                      y: frame.minY + normalized.minY * frame.height,
                      width: normalized.width * frame.width,
                      height: normalized.height * frame.height)
    }

    // MARK: - Display → Page normalized

    /// A rect drawn in container points (a drag selection) → page-normalized.
    /// Clamped to the page, so a drag that runs off the letterbox never produces
    /// out-of-range coordinates.
    static func pageRect(forDisplay rect: CGRect,
                         container: CGSize,
                         pixelSize: CGSize) -> CGRect {
        let frame = fittedImageFrame(container: container, pixelSize: pixelSize)
        guard frame.width > 0, frame.height > 0 else { return .zero }

        let raw = CGRect(x: (rect.minX - frame.minX) / frame.width,
                         y: (rect.minY - frame.minY) / frame.height,
                         width: rect.width / frame.width,
                         height: rect.height / frame.height)
        return raw.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Comparison helpers (used by ordering, dedupe, and future detectors)

    /// Intersection over union of two page-normalized rects.
    /// A future segmentation detector will use exactly this to decide which OCR
    /// regions fall inside a detected highlight mask.
    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let overlap = intersection.width * intersection.height
        let union = (a.width * a.height) + (b.width * b.height) - overlap
        guard union > 0 else { return 0 }
        return overlap / union
    }

    /// How much of `region` falls inside `area`, 0…1. The natural test for
    /// "is this line of text covered by this highlighter stroke".
    static func coverage(of region: CGRect, by area: CGRect) -> CGFloat {
        let intersection = region.intersection(area)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let regionArea = region.width * region.height
        guard regionArea > 0 else { return 0 }
        return (intersection.width * intersection.height) / regionArea
    }

    /// Shared horizontal extent relative to the narrower box. The companion to
    /// `verticalOverlapRatio`, and the test for whether an underline runs beneath
    /// a given line of text rather than beneath a different column.
    static func horizontalOverlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let left = max(a.minX, b.minX)
        let right = min(a.maxX, b.maxX)
        let shared = right - left
        guard shared > 0 else { return 0 }
        return shared / max(0.0001, min(a.width, b.width))
    }

    /// Shared vertical extent relative to the shorter box. Used to decide whether
    /// two OCR fragments sit on the same printed line.
    static func verticalOverlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let top = max(a.minY, b.minY)
        let bottom = min(a.maxY, b.maxY)
        let shared = bottom - top
        guard shared > 0 else { return 0 }
        return shared / max(0.0001, min(a.height, b.height))
    }
}
