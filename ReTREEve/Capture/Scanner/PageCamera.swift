//  PageCamera.swift
//  The camera ReTREEve owns.
//
//  ── WHY NOT VisionKit ──────────────────────────────────────────────────────
//
//  `DataScannerViewController` gave a beautiful viewfinder — live text
//  highlighting, framing guidance, all of it free. What it could not do on this
//  device was take the photograph:
//
//      AVFoundationErrorDomain -11800, underlying OSStatus -16800
//
//  on every single press, with the preview running perfectly the whole time.
//  VisionKit owns that capture session and exposes no frames, so there was
//  nothing to work around from outside: no retry, no restart, no reconfiguration
//  reaches the code that failed. The only fix was to stop asking it for photos.
//
//  So this file owns an `AVCaptureSession` directly. It is a plainer viewfinder
//  — no live text highlighting — in exchange for a shutter that works.
//
//  ── THREADING ──────────────────────────────────────────────────────────────
//
//  `AVCaptureSession` configuration and start/stop block, so they run on a
//  private queue and never on the main actor. The class is therefore
//  `nonisolated` and guards its own mutable state; `BookScannerModel` stays on
//  the main actor and talks to it through async methods.

import AVFoundation
import UIKit
import OSLog

nonisolated final class PageCamera: NSObject, @unchecked Sendable {

    enum CameraError: LocalizedError {
        case noCamera
        case configurationFailed
        case captureFailed(String)
        case busy

        var errorDescription: String? {
            switch self {
            case .noCamera:           "No camera is available on this device."
            case .configurationFailed: "The camera couldn't be set up."
            case .captureFailed(let reason): reason
            case .busy:               "A capture is already in progress."
            }
        }
    }

    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.retreeve.camera.session")
    private let lock = NSLock()

    private var device: AVCaptureDevice?
    private var pending: CheckedContinuation<UIImage, Error>?
    private var isConfigured = false

    /// A device with a back camera. False in the Simulator, which is why the
    /// scanner is never offered there.
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var isRunning: Bool { session.isRunning }

    // MARK: - Setup

    /// Builds the session once. Safe to call again; later calls do nothing.
    func configure() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                if isConfigured { continuation.resume(); return }

                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                           for: .video, position: .back) else {
                    continuation.resume(throwing: CameraError.noCamera)
                    return
                }

                session.beginConfiguration()
                session.sessionPreset = .photo

                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        continuation.resume(throwing: CameraError.configurationFailed)
                        return
                    }
                    session.addInput(input)
                    session.addOutput(output)
                } catch {
                    session.commitConfiguration()
                    continuation.resume(throwing: error)
                    return
                }

                // A page of small print is exactly the case that rewards the
                // largest dimensions the sensor offers: the OCR and the detector
                // both read this photo, and neither gets a second chance at it.
                output.maxPhotoQualityPrioritization = .quality
                if let largest = camera.activeFormat.supportedMaxPhotoDimensions.last {
                    output.maxPhotoDimensions = largest
                }

                session.commitConfiguration()

                // Autofocus and exposure biased for a flat page held close.
                if let _ = try? camera.lockForConfiguration() {
                    if camera.isFocusModeSupported(.continuousAutoFocus) {
                        camera.focusMode = .continuousAutoFocus
                    }
                    if camera.isAutoFocusRangeRestrictionSupported {
                        camera.autoFocusRangeRestriction = .near
                    }
                    if camera.isExposureModeSupported(.continuousAutoExposure) {
                        camera.exposureMode = .continuousAutoExposure
                    }
                    camera.unlockForConfiguration()
                }

                device = camera
                isConfigured = true
                continuation.resume()
            }
        }
    }

    /// The angle the VIEWFINDER is currently using, pushed in by the preview
    /// view. The photo is taken at exactly this angle, so what the reader framed
    /// is what they get.
    ///
    /// ── WHY NOT RotationCoordinator ────────────────────────────────────────
    ///
    /// This used `AVCaptureDevice.RotationCoordinator` and its
    /// `videoRotationAngleForHorizonLevel…` properties. Those derive "up" from
    /// GRAVITY, which is right for a camera pointed at a scene and wrong for
    /// this one: photographing a page means holding the phone flat, face down
    /// over a table. Gravity then runs along the lens axis, there is no horizon
    /// to level against, and the reported angle falls back to whatever was last
    /// resolved — which is how a portrait shot came back landscape, sometimes.
    ///
    /// Two further faults came with it. Preview and capture read two DIFFERENT
    /// properties, so the viewfinder could look right while the photo did not.
    /// And the preview angle was only refreshed in `layoutSubviews`, which a
    /// change in gravity never triggers, so it could sit stale indefinitely.
    ///
    /// Interface orientation has none of those problems: it is what the reader
    /// sees, it does not move when the phone is laid flat, and it always causes
    /// a layout pass — so the one refresh point is the correct one.
    private var rotationAngle: CGFloat = 90

    /// Called from the preview view on the main actor, where interface
    /// orientation can be read.
    func setRotationAngle(_ angle: CGFloat) {
        lock.lock(); rotationAngle = angle; lock.unlock()
    }

    private var captureRotationAngle: CGFloat {
        lock.lock(); defer { lock.unlock() }
        return rotationAngle
    }

    // MARK: - Running

    func start() {
        queue.async { [self] in
            guard isConfigured, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        guard session.isRunning else { throw CameraError.captureFailed("The camera isn't running.") }

        let angle = captureRotationAngle

        return try await withCheckedThrowingContinuation { continuation in
            // Claimed inside the closure so the check and the store are one
            // atomic step, and so the lock is never held across a suspension.
            lock.lock()
            if pending != nil {
                lock.unlock()
                continuation.resume(throwing: CameraError.busy)
                return
            }
            pending = continuation
            lock.unlock()

            queue.async { [self] in
                if let connection = output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }

                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                settings.maxPhotoDimensions = output.maxPhotoDimensions

                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func finish(_ result: Result<UIImage, Error>) {
        lock.lock()
        let continuation = pending
        pending = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

/// `nonisolated`: AVFoundation calls this back on its own queue, never the main
/// actor, and this module defaults to main-actor isolation.
nonisolated extension PageCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            Logger.capture.error("Photo capture failed: \(String(describing: error))")
            finish(.failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            finish(.failure(CameraError.captureFailed("The photo came back empty.")))
            return
        }
        // Orientation rides along in the file's EXIF, which is exactly what
        // `PageGeometry` expects to resolve at recognition time.
        finish(.success(image))
    }
}
