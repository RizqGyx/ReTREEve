//  AnnotationDetector.swift
//  VENDORED from the training repo (Anotation/ios_export/AnnotationDetector.swift).
//  Runs the exported YOLO26-nano segmentation model — nothing app-specific lives
//  here, so a re-export can overwrite this file wholesale.
//
//  Three deliberate deviations from the exported original, all of them things
//  the app needs and a standalone sample does not:
//
//    1. `init` throws instead of force-unwrapping the bundle URL. A missing model
//       must degrade to manual selection, never crash the capture flow.
//    2. The type is `nonisolated`, because this module defaults to MainActor
//       isolation and a couple of hundred milliseconds of inference has no
//       business running there.
//    3. `detect(image:)` requires an already-upright image. The original drew
//       `image.cgImage` into a rect sized from `image.size`, which silently
//       rotates the page when a photo carries EXIF orientation. Uprighting is
//       the caller's job now; `CoreMLMarkedPassageDetector` does it.
//
//  Everything else — the letterbox, the row layout, the mask maths — reproduces
//  the training-time transform exactly. Changing any of it means re-measuring.

import CoreML
import CoreImage
import UIKit

/// One detected reader annotation.
nonisolated struct Annotation: Sendable {
    enum Kind: Int, CaseIterable, Sendable {
        case highlight = 0, underline = 1, squiggly = 2, box = 3

        var name: String {
            switch self {
            case .highlight: return "highlight"
            case .underline: return "underline"
            case .squiggly:  return "squiggly"
            case .box:       return "box"
            }
        }
    }

    let kind: Kind
    let confidence: Float
    /// Bounding box in the coordinate space of the image passed to `detect`.
    let boundingBox: CGRect
    /// Binary mask cropped to `boundingBox`, row-major, width * height entries.
    let mask: [Bool]
    let maskWidth: Int
    let maskHeight: Int
}

enum AnnotationDetectorError: Error {
    /// The compiled model is not in the bundle — the .mlpackage was never added
    /// to the target, or the build did not compile it.
    case modelMissing
}

/// Runs the exported YOLO26-nano segmentation model.
///
/// The model takes a letterboxed 832x832 RGB image and returns 300 candidate
/// rows plus 32 mask prototypes. Each row is
/// `[x0, y0, x1, y1, confidence, classIndex, coeff0 ... coeff31]` in the
/// 832x832 letterboxed space, so boxes must be un-letterboxed before use.
nonisolated final class AnnotationDetector {

    private let model: MLModel
    private let inputSize = 832
    private let protoSize = 208
    private let protoCount = 32
    private let rowStride = 38
    private let maxDetections = 300

    init() throws {
        let config = MLModelConfiguration()
        // ── NOT `.all`, AND THAT IS MEASURED, NOT PREFERENCE ───────────────
        //
        // `.all` lets Core ML put this on the Neural Engine, which computes in
        // float16. For most models that is free accuracy-wise. For this one it
        // is not: the same photo that yields three highlights at 0.83/0.73/0.72
        // through CPU+GPU came back from the ANE as two detections topping out
        // at 0.79. Detections sitting near the confidence gate fall through it,
        // and a passage silently arrives one or two lines short.
        //
        // A page is captured once and read once, so a slower, exactly
        // reproducible answer is the right trade. If this is ever moved to a
        // live viewfinder, re-measure rather than reverting on principle.
        config.computeUnits = .cpuAndGPU
        guard let url = Bundle.main.url(forResource: "BookAnnotationDetector",
                                        withExtension: "mlmodelc") else {
            throw AnnotationDetectorError.modelMissing
        }
        model = try MLModel(contentsOf: url, configuration: config)
    }

    /// `image` must already be `.up` oriented — see the header note.
    func detect(image: UIImage, confidenceThreshold: Float = 0.25) throws -> [Annotation] {
        let (buffer, scale, padX, padY) = try letterbox(image)

        let input = try MLDictionaryFeatureProvider(dictionary: ["image": buffer])
        let output = try model.prediction(from: input)

        guard let detections = output.featureValue(for: "detections")?.multiArrayValue,
              let protos = output.featureValue(for: "maskProtos")?.multiArrayValue
        else { return [] }

        return decode(detections: detections, protos: protos,
                      threshold: confidenceThreshold,
                      scale: scale, padX: padX, padY: padY,
                      originalSize: image.size)
    }

    // MARK: - Preprocessing

    /// Resize preserving aspect ratio and pad with grey 114, matching the
    /// letterbox the model was trained with. Getting this wrong is the most
    /// common cause of results that differ from Python.
    private func letterbox(_ image: UIImage) throws
        -> (CVPixelBuffer, CGFloat, CGFloat, CGFloat) {

        let side = CGFloat(inputSize)
        let ratio = min(side / image.size.width, side / image.size.height)
        let newSize = CGSize(width: (image.size.width * ratio).rounded(),
                             height: (image.size.height * ratio).rounded())
        let padX = ((side - newSize.width) / 2).rounded(.down)
        let padY = ((side - newSize.height) / 2).rounded(.down)

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, inputSize, inputSize,
                            kCVPixelFormatType_32ARGB, attributes as CFDictionary,
                            &pixelBuffer)
        guard let buffer = pixelBuffer else {
            throw NSError(domain: "AnnotationDetector", code: 1)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: inputSize, height: inputSize, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            throw NSError(domain: "AnnotationDetector", code: 2)
        }

        context.setFillColor(red: 114/255, green: 114/255, blue: 114/255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        if let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(x: padX, y: padY,
                                             width: newSize.width,
                                             height: newSize.height))
        }

        return (buffer, ratio, padX, padY)
    }

    // MARK: - Decoding

    private func decode(detections: MLMultiArray, protos: MLMultiArray,
                        threshold: Float, scale: CGFloat,
                        padX: CGFloat, padY: CGFloat,
                        originalSize: CGSize) -> [Annotation] {

        let det = detections.dataPointer.bindMemory(
            to: Float.self, capacity: detections.count)
        let proto = protos.dataPointer.bindMemory(
            to: Float.self, capacity: protos.count)

        var results: [Annotation] = []

        for row in 0..<maxDetections {
            let base = row * rowStride
            let confidence = det[base + 4]
            guard confidence >= threshold,
                  let kind = Annotation.Kind(rawValue: Int(det[base + 5]))
            else { continue }

            // Un-letterbox into original image coordinates.
            let x0 = (CGFloat(det[base + 0]) - padX) / scale
            let y0 = (CGFloat(det[base + 1]) - padY) / scale
            let x1 = (CGFloat(det[base + 2]) - padX) / scale
            let y1 = (CGFloat(det[base + 3]) - padY) / scale

            let clamped = CGRect(x: max(0, x0), y: max(0, y0),
                                 width: min(originalSize.width, x1) - max(0, x0),
                                 height: min(originalSize.height, y1) - max(0, y0))
            guard clamped.width > 1, clamped.height > 1 else { continue }

            var coefficients = [Float](repeating: 0, count: protoCount)
            for k in 0..<protoCount { coefficients[k] = det[base + 6 + k] }

            let (mask, w, h) = buildMask(coefficients: coefficients, proto: proto,
                                         box: clamped, scale: scale,
                                         padX: padX, padY: padY)

            results.append(Annotation(kind: kind, confidence: confidence,
                                      boundingBox: clamped, mask: mask,
                                      maskWidth: w, maskHeight: h))
        }
        return results
    }

    /// mask = sigmoid(coefficients . prototypes), cropped to the box.
    private func buildMask(coefficients: [Float],
                           proto: UnsafeMutablePointer<Float>,
                           box: CGRect, scale: CGFloat,
                           padX: CGFloat, padY: CGFloat)
        -> ([Bool], Int, Int) {

        // Prototypes live at input resolution / 4.
        let downscale = CGFloat(inputSize / protoSize)
        let px0 = Int(((box.minX * scale + padX) / downscale).rounded(.down))
        let py0 = Int(((box.minY * scale + padY) / downscale).rounded(.down))
        let px1 = Int(((box.maxX * scale + padX) / downscale).rounded(.up))
        let py1 = Int(((box.maxY * scale + padY) / downscale).rounded(.up))

        let x0 = max(0, min(protoSize - 1, px0))
        let y0 = max(0, min(protoSize - 1, py0))
        let x1 = max(x0 + 1, min(protoSize, px1))
        let y1 = max(y0 + 1, min(protoSize, py1))

        let width = x1 - x0
        let height = y1 - y0
        var mask = [Bool](repeating: false, count: width * height)
        let planeSize = protoSize * protoSize

        for y in y0..<y1 {
            for x in x0..<x1 {
                var sum: Float = 0
                let offset = y * protoSize + x
                for k in 0..<protoCount {
                    sum += coefficients[k] * proto[k * planeSize + offset]
                }
                let probability = 1 / (1 + exp(-sum))
                mask[(y - y0) * width + (x - x0)] = probability > 0.5
            }
        }
        return (mask, width, height)
    }
}
