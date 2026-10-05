//  CaptureFlowView.swift
//  The capture task, start to commit. Presented as a full-screen modal because
//  it is self-contained, ends in a commit rather than a drill-down, and its
//  primary first step is a live camera.
//
//  This file COORDINATES ONLY. Every step is its own screen in Capture/; nothing
//  here knows about VisionKit, Vision, coordinates or selection. It owns the
//  flow's transient state (the frozen page, the draft passage) and decides what
//  follows what.
//
//      IMAGE ACQUISITION → TEXT RECOGNITION → MARKED-REGION SUGGESTION
//        → USER SELECTION → BOOK DETAILS → SAVE
//
//  Three entry points converge on the same confirmation screen:
//
//      Scan  → BookTextScannerView ──┐
//      Photo → PhotoImportView ───────┼→ PassageSelectionView ─┐
//                                                              ├→ InsightEditorView(.create)
//      Type  ─────────────────────────────────────────────────┘
//
//  None of the three is a fallback for another. Scan and Photo converge on an
//  identical `CapturedPage`, so nothing downstream — the detector included — can
//  tell which one produced it. Typing is the only path that works on hardware
//  without a Neural Engine or in the Simulator.
//
//  ── WHY THERE IS NO SEPARATE REVIEW SCREEN ─────────────────────────────────
//
//  The flow used to run Select → Review → Book Details: two confirmation screens
//  in a row about the same text, the second of which had so little to do that
//  its design filled the space with an illustration. Selection already shows the
//  assembled passage before Continue. The one thing Review added — correcting a
//  misread word — is now an Edit button on the passage card in Book Details,
//  where the reader already is. One screen fewer, nothing lost.
//
//  ── WHY SAVING RETURNS STRAIGHT TO HOME ─────────────────────────────────────
//
//  Saving is the most repeated action in the app. A success page would cost a
//  tap every single time just to leave it. Closing the flow and letting the
//  acorn land on the tree — with the Saved count ticking up beside it — says the
//  same thing, and says it where the reward actually lives.

import SwiftUI
import Observation

/// Transient state for one run through the capture flow.
///
/// A reference type on purpose. Navigation destinations are built from an
/// escaping closure, and reading `@State` value types through that closure is
/// not reliably fresh: the page was set and the step pushed in the same turn,
/// and the destination could still be built against a stale `nil`. A stable
/// observable reference is always current no matter when the closure captured it.
@Observable
final class CaptureFlowState {
    var capturedPage: CapturedPage?
    var draftPassage = ""
}

struct CaptureFlowView: View {
    /// Called after an insight was saved, once the flow has closed.
    var onSaved: () -> Void = {}

    /// The marked-passage detector this flow runs before manual selection.
    /// Injected here so the implementation is one default argument rather than a
    /// change to any of the screens. See `MarkedPassageDetecting`.
    ///
    /// The V3 segmentation model ships here. Where the model is missing from the
    /// bundle it reports itself unavailable, and the selection screen is the
    /// manual screen it has always been — pass `NoopMarkedPassageDetector()` to
    /// get that behaviour deliberately.
    var detector: any MarkedPassageDetecting = CoreMLMarkedPassageDetector()

    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    /// The photo picker is a sheet rather than a step: a step would put the
    /// system picker inside the flow's navigation bar and back button.
    @State private var isImportingPhoto = false

    /// Deliberately not in the Step enum: a `CapturedPage` holds a UIImage and
    /// has no business being Hashable or living inside a navigation path.
    @State private var flow = CaptureFlowState()

    private enum Step: Hashable {
        case scanner
        case select
        case confirm
    }

    var body: some View {
        NavigationStack(path: $path) {
            CaptureSourceView(
                onScan: { path.append(Step.scanner) },
                onUsePhoto: { isImportingPhoto = true },
                onTypeItOut: { startTyping() }
            )
            .navigationDestination(for: Step.self) { step in destination(for: step) }
            .toolbar {
                // A modal's first screen closes; it has nothing to go back to.
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .tint(Grimoire.primary)
        .sheet(isPresented: $isImportingPhoto) {
            PhotoImportView(
                onPageCaptured: { page in
                    isImportingPhoto = false
                    flow.capturedPage = page
                    path.append(Step.select)
                },
                onCancel: { isImportingPhoto = false }
            )
        }
    }

    @ViewBuilder
    private func destination(for step: Step) -> some View {
        switch step {
        case .scanner:
            BookTextScannerView(
                onPageCaptured: { page in
                    flow.capturedPage = page
                    path.append(Step.select)
                },
                onUsePhoto: { isImportingPhoto = true },
                onTypeInstead: { startTyping() }
            )

        case .select:
            if let page = flow.capturedPage {
                PassageSelectionView(page: page, detector: detector) { passage in
                    flow.draftPassage = passage
                    path.append(Step.confirm)
                }
            } else {
                // Unreachable in normal use, but a missing page must never leave
                // the reader on a blank screen with no way forward.
                recovery("That page was lost before it could be read.")
            }

        case .confirm:
            InsightEditorView(mode: .create,
                              initialPassage: flow.draftPassage,
                              lowConfidenceCount: lowConfidenceCount,
                              onDone: {
                                  dismiss()
                                  onSaved()
                              })
        }
    }

    /// How many lines on the captured page were read with low confidence.
    /// Drives a gentle "worth a check" hint on the passage card.
    private var lowConfidenceCount: Int {
        guard let page = flow.capturedPage else { return 0 }
        return page.regions.filter(\.isLowConfidence).count
    }

    /// The typed path, reachable from the source screen and from every
    /// scanner-unavailable state.
    private func startTyping() {
        flow.draftPassage = ""
        flow.capturedPage = nil
        path.append(Step.confirm)
    }

    private func recovery(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image("Squirrel").resizable().scaledToFit().frame(width: 96).accessibilityHidden(true)
            Text(message)
                .font(.grimoire(.headline, .emphasized))
                .foregroundStyle(Grimoire.textPrimary)
                .multilineTextAlignment(.center)
            Button {
                startTyping()
            } label: {
                Label("Type Manually", systemImage: "square.and.pencil")
            }
            .buttonStyle(GrimoirePrimaryButton())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .magicalBackground(.subtle)
    }
}

/// Where a passage comes from — "Pick Method" in the design.
///
/// Titled "New Insight" on screen rather than "Pick Method": the reader arrived
/// by tapping New Insight, and a method is the designer's word for the choice,
/// not the reader's. Order carries the hierarchy — scanning a marked page is the
/// product, so it comes first — which lets the three cards look like equals, as
/// the design draws them.
struct CaptureSourceView: View {
    var onScan: () -> Void
    var onUsePhoto: () -> Void
    var onTypeItOut: () -> Void

    private var canScan: Bool { BookScannerModel.isScanningSupported }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Text("How would you like to add an insight?")
                        .font(.grimoire(.body))
                        .foregroundStyle(Grimoire.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    if canScan {
                        method(title: "Scan a Marked Page",
                               detail: "Capture a passage you've marked in your physical book.",
                               icon: "doc.viewfinder",
                               action: onScan)
                    } else {
                        scanUnavailable
                    }

                    method(title: "Import Photo",
                           detail: "Choose a photo of a marked book page.",
                           icon: "photo.fill",
                           action: onUsePhoto)

                    method(title: "Type Manually",
                           detail: "Type or paste the passage yourself.",
                           icon: "square.and.pencil",
                           action: onTypeItOut)

                    Spacer(minLength: 16)

                    Image("Squirrel")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150)
                        .gentleFloat(amplitude: 3, duration: 3.4)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                // Short content fills the screen so the squirrel rests at the
                // bottom; long content (large text sizes) simply scrolls.
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .magicalBackground(.normal)
        .grimoireNavigationTitle("New Insight")
    }

    private func method(title: String,
                        detail: String,
                        icon: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.grimoire(.title1))
                    .foregroundStyle(Grimoire.primary)
                    .frame(minWidth: 48, minHeight: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.grimoire(.headline))
                        .foregroundStyle(Grimoire.textPrimary)
                    Text(detail)
                        .font(.grimoire(.footnote))
                        .foregroundStyle(Grimoire.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Grimoire.primary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Grimoire.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Grimoire.border, lineWidth: 1))
            .shadow(color: Grimoire.textPrimary.opacity(0.12), radius: 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(.isButton)
    }

    private var scanUnavailable: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.grimoire(.title1))
                .foregroundStyle(Grimoire.textDisabled)
                .frame(minWidth: 48, minHeight: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanning isn't available here")
                    .font(.grimoire(.headline))
                    .foregroundStyle(Grimoire.textSecondary)
                Text("This device doesn't have a camera ReTREEve can use.")
                    .font(.grimoire(.footnote))
                    .foregroundStyle(Grimoire.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Grimoire.secondarySoft,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Grimoire.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .accessibilityElement(children: .combine)
    }
}
