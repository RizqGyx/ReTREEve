//  BookScannerModel.swift
//  Availability, permission and capture state for the page scanner.
//
//  Every unhappy path is a named case rather than a silent failure, because each
//  one needs different words and a different action: an unsupported device can
//  never scan, a denied permission can be fixed in Settings, and a transient
//  failure just needs another try. All of them leave typing and the photo
//  library available.
//
//  ── THE CAMERA IS OURS NOW ─────────────────────────────────────────────────
//
//  This used to drive `DataScannerViewController` and ask it for photos. On the
//  device this app is developed against, that request failed every time with
//  AVFoundation -11800 while its preview ran perfectly — a failure inside a
//  session VisionKit owns and does not expose. See `PageCamera` for the full
//  reasoning. The state machine below is unchanged; only what sits behind
//  `captureAndRead()` is different.

import Foundation
import Observation
import OSLog
import UIKit
import AVFoundation

@Observable
final class BookScannerModel {

    enum Status: Equatable {
        /// Checking support and permission.
        case preparing
        /// No camera. Never recoverable — this is the Simulator, mostly.
        case unsupported
        /// The reader said no, or has not been asked yet and declined.
        case permissionDenied
        /// Parental controls or MDM. Not the reader's to fix.
        case permissionRestricted
        /// Camera live, ready to capture.
        case scanning
        /// Recoverable — the reader can try again.
        case failed(String)
    }

    var status: Status = .preparing

    /// Set while the photo is being taken and read. Drives the shutter's
    /// disabled state so a page cannot be captured twice.
    var isWorking = false
    var workingMessage = ""

    /// Non-fatal, shown inline over the live preview.
    var transientError: String?

    /// The photograph just taken, shown in place of the viewfinder from the
    /// moment it exists until the reader comes back to this screen.
    ///
    /// Without it the preview kept running behind the "reading" card: the page
    /// had already been captured, but the image on screen still followed every
    /// movement of the phone, which reads as the capture not having happened —
    /// or as the app still waiting for the reader to hold still. Freezing on the
    /// captured frame says, unambiguously, "this is what I'm reading."
    var capturedStill: UIImage?

    /// Owned outright, unlike the view controller this replaced. The preview
    /// borrows it; the model decides when it runs.
    let camera = PageCamera()

    private let recognizer: any TextRecognizing

    init(recognizer: any TextRecognizing = VisionTextRecognizer()) {
        self.recognizer = recognizer
    }

    var isScanning: Bool { status == .scanning }

    /// True only where the hardware can actually do this, so the reader is never
    /// sent into a dead end.
    static var isScanningSupported: Bool {
        PageCamera.isAvailable
    }

    // MARK: - Lifecycle

    func prepare() async {
        guard PageCamera.isAvailable else {
            status = .unsupported
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { status = .permissionDenied; return }
        case .denied:
            status = .permissionDenied
            return
        case .restricted:
            status = .permissionRestricted
            return
        @unknown default:
            status = .permissionDenied
            return
        }

        do {
            try await camera.configure()
        } catch {
            Logger.capture.error("Camera configuration failed: \(String(describing: error))")
            status = .failed(error.localizedDescription)
            return
        }

        camera.start()
        status = .scanning
    }

    /// Starts the camera if it is not already running. Safe to call as often as
    /// it takes: the session is asked, never a remembered flag, so returning to
    /// this screen or to the foreground always restores a live preview.
    func resumeScanningIfNeeded() {
        guard case .scanning = status else { return }
        // A frozen still is on screen: the camera stays off behind it, or a
        // return to the foreground would restart a feed nobody can see.
        guard capturedStill == nil else { return }
        guard !camera.isRunning else { return }
        camera.start()
    }

    /// Drops the frozen still and brings the live camera back. Called when the
    /// reader returns to the scanner, e.g. with Back from passage selection.
    func returnToLiveCamera() {
        capturedStill = nil
        resumeScanningIfNeeded()
    }

    func pauseScanning() {
        camera.stop()
    }

    // MARK: - Capture

    /// Freezes the page and reads it. Returns `nil` on any failure, having
    /// already set an error the view can show; the camera stays live so the
    /// reader can simply try again.
    func captureAndRead() async -> CapturedPage? {
        guard !isWorking else { return nil }

        isWorking = true
        transientError = nil
        capturedStill = nil
        defer { isWorking = false }

        workingMessage = "Capturing the page…"
        resumeScanningIfNeeded()

        let image: UIImage
        do {
            image = try await camera.capturePhoto()
        } catch {
            Logger.capture.error("capturePhoto failed: \(String(describing: error))")
            transientError = Self.captureFailureMessage(error)
            return nil
        }

        // Freeze: the still replaces the viewfinder, and the live feed stops so
        // nothing moves behind it while the page is read.
        capturedStill = image
        pauseScanning()

        do {
            workingMessage = "Finding your marked passage…"
            // On success the still stays up through the hand-off to selection,
            // so there is no flash of a stopped preview between the two screens.
            return try await recognizer.recognizePage(in: image)
        } catch let error as TextRecognitionError {
            transientError = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
            returnToLiveCamera()
            return nil
        } catch {
            transientError = "We couldn't read this page clearly. Try again."
            returnToLiveCamera()
            return nil
        }
    }

    /// The reader gets one sentence they can act on. A developer running a debug
    /// build gets the underlying error too, because "hold steady" is a guess, and
    /// a capture that fails for a structural reason will never be fixed by
    /// holding steadier.
    private static func captureFailureMessage(_ error: Error) -> String {
        let advice = "Couldn't capture the page. Hold steady and try again, or use a photo instead."
        return advice
    }

    // MARK: - Settings

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension Logger {
    /// `nonisolated`: detection and capture both log from off the main actor.
    nonisolated static let capture = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReTREEve",
                                            category: "capture")
}
