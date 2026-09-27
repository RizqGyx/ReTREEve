//  CameraPreviewRepresentable.swift
//  The viewfinder: an AVCaptureVideoPreviewLayer, and nothing else.
//
//  The layer is the view's own backing layer rather than a sublayer, so it is
//  sized and rotated by UIKit's layout rather than by hand-written frame maths
//  that would need re-doing on every rotation.

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewRepresentable: UIViewRepresentable {
    let camera: PageCamera

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.camera = camera
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        view.applyRotation()
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var camera: PageCamera?

    /// Layout is the one moment that reliably follows an interface rotation, so
    /// the angle is refreshed here rather than through a separate observer.
    ///
    /// This is only a correct refresh point because the angle now comes from
    /// interface orientation. It was not one while the angle came from gravity:
    /// tilting a phone flat over a table changes gravity without changing a
    /// single bound, so nothing called this and the preview went stale.
    override func layoutSubviews() {
        super.layoutSubviews()
        applyRotation()
    }

    /// One angle, computed once, applied to the viewfinder AND handed to the
    /// camera for the shutter. Preview and capture cannot disagree because they
    /// are no longer two separate calculations.
    func applyRotation() {
        guard let camera else { return }
        let angle = Self.rotationAngle(
            for: window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait)

        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        camera.setRotationAngle(angle)
    }

    /// Degrees the video must be rotated to stand upright for a given interface
    /// orientation, on a back camera.
    static func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:           90
        case .portraitUpsideDown: 270
        case .landscapeLeft:      180
        case .landscapeRight:     0
        default:                  90
        }
    }
}
