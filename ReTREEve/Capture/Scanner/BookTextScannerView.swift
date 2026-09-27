//  BookTextScannerView.swift
//  Screen: point the camera at the marked page and freeze it.
//
//  Coordinates nothing beyond its own screen — it hands a finished CapturedPage
//  upward and lets CaptureFlowView decide where that goes.
//
//  ── LAYOUT ─────────────────────────────────────────────────────────────────
//
//  The camera runs edge to edge beneath the navigation bar, with one white frame
//  to fill, one line of instruction and one labelled button. The alternative
//  design put botanical bands above and below the camera and a blank round
//  shutter under it; that spends a third of the screen on decoration exactly
//  where the page needs the pixels, and a blank circle asks a first-time reader
//  to guess. Importing a photo and typing are one step back, on the method
//  screen, and in every state where the camera cannot help.

import SwiftUI

struct BookTextScannerView: View {
    /// Called once a page has been captured AND read.
    var onPageCaptured: (CapturedPage) -> Void
    /// The other way to get a page. Offered wherever the camera disappoints,
    /// because it shares none of the camera's machinery and so fails independently.
    var onUsePhoto: () -> Void
    /// Escape hatch offered in every unavailable state, so the screen is never a dead end.
    var onTypeInstead: () -> Void

    @State private var model = BookScannerModel()

    /// Watched because the system stops the capture session when the app leaves
    /// the foreground and does not restart it on the way back.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch model.status {
            case .preparing:
                preparing
            case .scanning:
                livePreview
            case .unsupported:
                unavailable(
                    title: "This device can't scan",
                    message: "Scanning needs a camera. You can still import a photo or type the passage yourself.",
                    systemImage: "iphone.slash")
            case .permissionDenied:
                unavailable(
                    title: "Camera Access Needed",
                    message: "Allow camera access to scan marked pages. You can also import a photo or type the passage yourself.",
                    systemImage: "camera.fill",
                    primary: ("Open Settings", { model.openSystemSettings() }))
            case .permissionRestricted:
                unavailable(
                    title: "Camera access is restricted",
                    message: "Camera use is limited on this device by Screen Time or a device policy. You can still write the passage out yourself.",
                    systemImage: "lock.fill")
            case .failed(let reason):
                unavailable(
                    title: "The camera didn't start",
                    message: reason,
                    systemImage: "exclamationmark.triangle.fill",
                    primary: ("Try Again", { Task { await model.prepare() } }))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only the strip behind the navigation bar shows while the camera runs,
        // so the full illustration fits there; the text-heavy states get it faded.
        .magicalBackground(model.isScanning ? .normal : .subtle)
        .grimoireNavigationTitle("Scan a Marked Page")
        .task { await model.prepare() }
        .onChange(of: scenePhase) { _, phase in
            // The camera is released while the app is away rather than left
            // holding hardware it cannot use, and restored on the way back.
            switch phase {
            case .active:     model.resumeScanningIfNeeded()
            case .background: model.pauseScanning()
            default:          break
            }
        }
    }

    // MARK: - Live preview

    private var livePreview: some View {
        ZStack {
            CameraPreviewRepresentable(camera: model.camera)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
                // Returning here from the selection screen leaves the frozen
                // still up and the session stopped. This drops the still and
                // restarts the feed, so a second scan works like the first.
                .onAppear { model.returnToLiveCamera() }
                .accessibilityLabel("Camera viewfinder")
                .accessibilityHint("Fit the page inside the frame, then use the capture button")

            // Sits over a live camera, so it is not a palette colour: whatever
            // the page underneath looks like, the controls must stay legible.
            LinearGradient(colors: [.clear, .black.opacity(0.35)],
                           startPoint: UnitPoint(x: 0.5, y: 0.55),
                           endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ZStack(alignment: .bottom) {
                framingGuide
                controls
            }
        }
        .overlay {
            // Fully opaque. The old overlay was black at 35%, so the live camera
            // showed through and kept moving while the page was being read.
            if model.isWorking || model.capturedStill != nil {
                ZStack {
                    Color.black.ignoresSafeArea()

                    if let still = model.capturedStill {
                        // `.scaledToFill` matches the preview layer's
                        // `.resizeAspectFill`, so the frozen frame lines up with
                        // exactly what the reader had framed.
                        Image(uiImage: still)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                            .clipped()
                        Color.black.opacity(0.4).ignoresSafeArea()
                    }

                    if model.isWorking {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(Grimoire.primary)
                            Text(model.workingMessage)
                                .font(.grimoire(.subhead))
                                .foregroundStyle(Grimoire.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(26)
                        .background(Grimoire.surface,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                // Opaque to touches as well as to sight: no second capture while
                // the first page is still being read.
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.isWorking ? model.workingMessage : "Captured page")
            }
        }
    }

    /// A frame to fill, drawn without claiming to have recognised anything. It
    /// ends behind the middle of the capture button, so the frame and the action
    /// read as one unit.
    private var framingGuide: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Grimoire.surface, lineWidth: 2)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8 + Grimoire.buttonHeight / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if let error = model.transientError {
                Text(error)
                    .font(.grimoire(.subhead))
                    .foregroundStyle(Grimoire.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Grimoire.destructiveSoft,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityAddTraits(.isStaticText)
            } else {
                Text("Fit the page inside the frame and make sure the text is sharp.")
                    .font(.grimoire(.subhead))
                    .foregroundStyle(Grimoire.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Grimoire.surface,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                    .accessibilityHidden(true)
            }

            Button {
                Task {
                    if let page = await model.captureAndRead() { onPageCaptured(page) }
                }
            } label: {
                Label(model.isWorking ? model.workingMessage : "Capture Page",
                      systemImage: "camera.fill")
            }
            .buttonStyle(GrimoirePrimaryButton())
            .disabled(model.isWorking)
            .accessibilityLabel("Capture page")
            .accessibilityHint("Freezes the page and finds your marked passage")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var preparing: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Getting the camera ready…")
                .font(.grimoire(.subhead))
                .foregroundStyle(Grimoire.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Unavailable states

    /// Every one of these keeps typing reachable, so no state is a dead end.
    private func unavailable(title: String,
                             message: String,
                             systemImage: String,
                             primary: (String, () -> Void)? = nil) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Image("Squirrel").resizable().scaledToFit().frame(width: 96).accessibilityHidden(true)
                    .padding(.top, 12)

                Image(systemName: systemImage)
                    .font(.grimoire(.title2))
                    .foregroundStyle(Grimoire.textSecondary)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.grimoire(.title3, .emphasized))
                    .foregroundStyle(Grimoire.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.grimoire(.subhead))
                    .foregroundStyle(Grimoire.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let primary {
                    Button(primary.0, action: primary.1)
                        .buttonStyle(GrimoirePrimaryButton())
                        .padding(.top, 4)
                }

                Button {
                    onUsePhoto()
                } label: {
                    Label("Import Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(primary == nil ? AnyButtonStyleBox(GrimoirePrimaryButton()) : AnyButtonStyleBox(GrimoireSecondaryButton()))

                Button {
                    onTypeInstead()
                } label: {
                    Label("Type Manually", systemImage: "square.and.pencil")
                }
                .buttonStyle(AnyButtonStyleBox(GrimoireSecondaryButton()))
            }
            .padding(24)
        }
    }
}

/// Lets one call site pick between the app's two button styles without
/// duplicating the label. Purely local plumbing.
private struct AnyButtonStyleBox: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { configuration in AnyView(style.makeBody(configuration: configuration)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
