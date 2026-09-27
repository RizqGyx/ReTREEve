//  PassageSelectionView.swift
//  Screen: "which of this did you mark?"
//
//  Selection is SPATIAL, never structural. The reader picks regions off the
//  frozen page; nothing here assumes an OCR region is a paragraph, a sentence or
//  even a whole line, because on a real book page it frequently is none of those.
//
//  Two interactions, because one alone is wrong for one of the two common cases:
//    • TAP a line — precise, right for a single marked sentence.
//    • DRAG across lines — right for a highlight spanning half a page, where
//      tapping fourteen lines individually would be absurd.
//  Order of interaction is irrelevant: the passage is assembled in reading
//  order, not tap order.
//
//  ── ONE CARD, THREE STATES ─────────────────────────────────────────────────
//
//  The card above Continue is the whole conversation, so there is no banner at
//  the top competing with it:
//    • looking      — the detector is still running
//    • found        — the detector preselected a passage; the card shows its text
//    • nothing      — no mark found; the card says how to select by hand
//  The text in the card is the review. Seeing the passage before Continue is
//  what the old separate review screen was for.

import SwiftUI

struct PassageSelectionView: View {
    let page: CapturedPage
    var detector: any MarkedPassageDetecting = NoopMarkedPassageDetector()
    var onContinue: (String) -> Void

    @State private var selection: Set<RecognizedTextRegion.ID> = []

    /// How far across each line the detector's mark ran, so the passage can come
    /// back as the phrase that was marked rather than the lines containing it.
    ///
    /// An entry is dropped the moment the reader touches that line themselves. A
    /// tap carries no span — it says "this line" — and silently keeping a
    /// detector's narrowing after the reader has overridden it would hand them a
    /// fragment of a line they deliberately chose whole.
    @State private var markedSpans: [RecognizedTextRegion.ID: ClosedRange<CGFloat>] = [:]

    /// The detector preselected the current selection.
    @State private var foundAutomatically = false
    /// The reader has changed the selection themselves since.
    @State private var readerAdjusted = false
    @State private var isDetecting = true
    @State private var dragOrigin: CGPoint?
    @State private var dragPoint: CGPoint?

    private var selectedRegions: [RecognizedTextRegion] {
        page.regions.filter { selection.contains($0.id) }
    }

    private var assembledPassage: String {
        PassageAssembler.passage(from: selectedRegions, marked: markedSpans)
    }

    private var showsFoundState: Bool { foundAutomatically && !readerAdjusted }

    var body: some View {
        VStack(spacing: 0) {
            pageCanvas
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { selectionBar }
        .magicalBackground(.normal)
        .grimoireNavigationTitle("Select Passage")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.isEmpty ? "Select All" : "Clear") {
                    if selection.isEmpty {
                        selection = Set(page.regions.map(\.id))
                    } else {
                        selection.removeAll()
                    }
                    markedSpans.removeAll()
                    readerAdjusted = true
                }
                .font(.grimoire(.subhead))
            }
        }
        .task { await runDetection() }
    }

    // MARK: - Automatic detection (AI SUGGESTS, HUMAN CONFIRMS)

    /// Runs whatever detector was injected. Where none is available the screen
    /// is simply the manual selection screen — no error, no degraded state.
    private func runDetection() async {
        defer { isDetecting = false }

        guard detector.isAvailable else { return }

        // Already ranked by the detector — most text claimed first. Taking the
        // most confident instead would reinstate the page-number problem.
        let suggestions = await detector.suggestMarkedPassages(on: page)
        guard let best = suggestions.first, !best.regionIDs.isEmpty else { return }

        // Preselected, never auto-committed. The reader still presses Continue.
        selection = Set(best.regionIDs)
        markedSpans = best.markedSpans
        foundAutomatically = true
    }

    // MARK: - The page

    private var pageCanvas: some View {
        GeometryReader { proxy in
            let container = proxy.size

            ZStack(alignment: .topLeading) {
                Image(uiImage: page.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: container.width, height: container.height)
                    // The photo itself carries no information VoiceOver can use;
                    // the text is exposed through the region buttons below.
                    .accessibilityHidden(true)

                ForEach(page.regions) { region in
                    regionOverlay(region, container: container)
                }

                if let rect = dragRect {
                    Rectangle()
                        .strokeBorder(Grimoire.accentMagic, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .background(Rectangle().fill(Grimoire.accentMagic.opacity(0.12)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            // `simultaneousGesture` with a real minimum distance so region
            // buttons still receive plain taps; only actual dragging rubber-bands.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = value.startLocation }
                        dragPoint = value.location
                    }
                    .onEnded { value in
                        defer { dragOrigin = nil; dragPoint = nil }
                        guard let origin = dragOrigin else { return }
                        let display = CGRect(x: min(origin.x, value.location.x),
                                             y: min(origin.y, value.location.y),
                                             width: abs(value.location.x - origin.x),
                                             height: abs(value.location.y - origin.y))
                        selectRegions(inDisplayRect: display, container: container)
                    }
            )
        }
        // No colour behind the page. A plain `.background(Color)` extends into
        // every safe area, so it painted over the botanical background under the
        // navigation bar and behind the selection card as well.
    }

    private var dragRect: CGRect? {
        guard let origin = dragOrigin, let point = dragPoint else { return nil }
        return CGRect(x: min(origin.x, point.x),
                      y: min(origin.y, point.y),
                      width: abs(point.x - origin.x),
                      height: abs(point.y - origin.y))
    }

    private func regionOverlay(_ region: RecognizedTextRegion, container: CGSize) -> some View {
        let frame = PageGeometry.displayRect(for: region.boundingBox,
                                             container: container,
                                             pixelSize: page.pixelSize)
        let isSelected = selection.contains(region.id)

        return Button {
            toggle(region)
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? Grimoire.accentMagic.opacity(0.30) : Grimoire.primary.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(isSelected ? Grimoire.accentMagic : Grimoire.primary.opacity(0.45),
                                      lineWidth: isSelected ? 1.5 : 0.75)
                )
        }
        .buttonStyle(.plain)
        .frame(width: max(frame.width, 8), height: max(frame.height, 8))
        .position(x: frame.midX, y: frame.midY)
        .accessibilityLabel(region.text)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to remove this line from your passage"
                                      : "Double tap to add this line to your passage")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Selection

    private func toggle(_ region: RecognizedTextRegion) {
        readerAdjusted = true
        // A tap is the reader overruling the detector about this line, and it
        // says nothing about which words. Whatever narrowing the detector had
        // applied here stops applying.
        markedSpans.removeValue(forKey: region.id)

        if selection.contains(region.id) {
            selection.remove(region.id)
        } else {
            selection.insert(region.id)
        }
    }

    /// Adds every region whose box is meaningfully covered by the dragged area.
    /// A coverage test rather than a plain intersection so that grazing the edge
    /// of a neighbouring line does not sweep it in.
    private func selectRegions(inDisplayRect display: CGRect, container: CGSize) {
        let area = PageGeometry.pageRect(forDisplay: display,
                                         container: container,
                                         pixelSize: page.pixelSize)
        guard !area.isEmpty else { return }

        let hits = page.regions.filter {
            PageGeometry.coverage(of: $0.boundingBox, by: area) > 0.35
        }
        guard !hits.isEmpty else { return }
        readerAdjusted = true
        for region in hits {
            selection.insert(region.id)
            // Same reasoning as a tap: a drag chose lines, not words.
            markedSpans.removeValue(forKey: region.id)
        }
    }

    // MARK: - Bottom bar

    private var selectionBar: some View {
        VStack(spacing: 12) {
            selectionCard

            Button("Continue") {
                onContinue(assembledPassage)
            }
            .buttonStyle(GrimoirePrimaryButton())
            .disabled(assembledPassage.isEmpty)
            .opacity(assembledPassage.isEmpty ? 0.55 : 1)
            .accessibilityHint(assembledPassage.isEmpty
                               ? "Select the lines you marked first"
                               : "Uses this passage and goes to book details")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selection.isEmpty {
                HStack(spacing: 8) {
                    if isDetecting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Grimoire.primary)
                    }
                    Text(isDetecting ? "Looking for your marked passage…" : "No marked passage found")
                        .font(.grimoire(.subhead, .emphasized))
                        .foregroundStyle(Grimoire.textPrimary)
                }
                if !isDetecting {
                    Text("Tap the lines you marked, or drag across several.")
                        .font(.grimoire(.footnote))
                        .foregroundStyle(Grimoire.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(showsFoundState ? "Marked Passage Found" : "Selected Passage")
                    .font(.grimoire(.subhead, .emphasized))
                    .foregroundStyle(Grimoire.textPrimary)

                HStack(alignment: .top, spacing: 8) {
                    PassageQuoteMark(size: 16)
                        .padding(.top, 2)
                    Text(assembledPassage)
                        .font(.grimoire(.subhead))
                        .foregroundStyle(Grimoire.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(showsFoundState
                     ? "Not quite right? Tap lines to add or remove them."
                     : "Tap lines to add or remove them. Drag to select several.")
                    .font(.grimoire(.caption1))
                    .foregroundStyle(Grimoire.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Grimoire.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Grimoire.border, lineWidth: 1))
        .shadow(color: Grimoire.textPrimary.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}
