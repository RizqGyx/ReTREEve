import SwiftUI

struct SearchView: View {
    @State private var recall = ""
    @FocusState private var focused: Bool

    @State private var voice = VoiceDictation()

    @State private var recallBeforeDictation = ""

    @State private var levels: [Double] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxLength = 500
    private static let waveformBars = 36

    private var trimmedRecall: String {
        recall.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let ideas = ["trust", "habit", "focus", "fear", "motivation"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                inputCard

                if voice.isListening {
                    listeningPanel
                        .transition(.opacity)
                } else {
                    if let message = voiceMessage {
                        voiceMessageCard(message)
                    }
                    ideasSection
                    companion
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: voice.isListening)
        }
        .scrollDismissesKeyboard(.interactively)
        .magicalBackground(.subtle)
        .navigationTitle("Find Again")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { searchBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .task {
            SemanticExpansion.prewarm()
        }
        .onDisappear { voice.stop() }
        .onChange(of: recall) { _, text in
            if text.count > Self.maxLength { recall = String(text.prefix(Self.maxLength)) }
        }
        .onChange(of: voice.transcript) { _, spoken in
            guard voice.isListening else { return }
            let joined = recallBeforeDictation.isEmpty
                ? spoken
                : recallBeforeDictation + " " + spoken
            recall = String(joined.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maxLength))
        }
        .onChange(of: voice.level) { _, level in
            guard voice.isListening else { return }
            levels.append(level)
            if levels.count > Self.waveformBars {
                levels.removeFirst(levels.count - Self.waveformBars)
            }
        }
        .onChange(of: voice.isListening) { _, listening in
            if listening { levels.removeAll() }
        }
        .onChange(of: voice.status) { _, status in
            switch status {
            case .unavailable, .failed: focused = true
            default: break
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(voice.isListening ? "Say what you remember" : "What do you still remember?")
                .font(.grimoire(.title1, .emphasized))
                .foregroundStyle(Grimoire.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(voice.isListening
                 ? "Speak naturally. We'll find possible matches, even if it's not exact."
                 : "Even a few words can be enough. Try describing the idea, feeling, or situation.")
                .font(.grimoire(.subhead))
                .foregroundStyle(Grimoire.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Something about trust, being careful, and bad things happening…",
                      text: $recall, axis: .vertical)
                .font(.grimoire(.body))
                .foregroundStyle(Grimoire.textPrimary)
                .lineLimit(5...10)
                .focused($focused)
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                .accessibilityLabel("What you remember")

            HStack(alignment: .center) {
                Text("\(recall.count)/\(Self.maxLength)")
                    .font(.grimoire(.caption2).monospacedDigit())
                    .foregroundStyle(recall.count >= Self.maxLength
                                     ? Grimoire.accentMagic : Grimoire.textDisabled)
                    .accessibilityLabel("\(recall.count) of \(Self.maxLength) characters")

                Spacer()

                if VoiceDictation.isSupported {
                    micButton
                }
            }
        }
        .grimoireCard(padding: 16, radius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(focused ? Grimoire.primary.opacity(0.5) : .clear, lineWidth: 1.5))
    }

    private var micButton: some View {
        Button {
            Task { await toggleDictation() }
        } label: {
            Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(voice.isListening ? Grimoire.surface : Grimoire.primary)
                .frame(width: 44, height: 44)
                .background(voice.isListening ? Grimoire.primary : Grimoire.primarySoft,
                            in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice.isListening ? "Stop listening" : "Start voice search")
        .accessibilityHint(voice.isListening
                           ? "Ends dictation and keeps what was heard"
                           : "Speak what you remember instead of typing")
    }

    private var listeningPanel: some View {
        VStack(spacing: 16) {
            Button {
                Task { await toggleDictation() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Grimoire.accentMystic.opacity(0.10))
                        .frame(width: 190 + 30 * voice.level, height: 190 + 30 * voice.level)
                        .blur(radius: 10)
                    Circle()
                        .strokeBorder(Grimoire.accentMagic.opacity(0.55), lineWidth: 3)
                        .frame(width: 148 + 24 * voice.level, height: 148 + 24 * voice.level)
                    Circle()
                        .fill(Grimoire.primary)
                        .frame(width: 124, height: 124)
                        .shadow(color: Grimoire.accentMagic.opacity(0.45), radius: 16)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Grimoire.surface)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: voice.level)
            .accessibilityLabel("Stop listening")

            waveform
                .frame(height: 32)

            Text("Listening…")
                .font(.grimoire(.subhead))
                .foregroundStyle(Grimoire.textPrimary)

            Button("Tap to stop listening") {
                voice.stop()
            }
            .font(.grimoire(.footnote))
            .foregroundStyle(Grimoire.textSecondary)
            .frame(minHeight: 44)

            if !voice.isOnDevice {
                Text("This language is transcribed by Apple rather than on your device. Typing never leaves your device.")
                    .font(.grimoire(.caption1))
                    .foregroundStyle(Grimoire.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var waveform: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let barWidth = max(1.5,
                               (proxy.size.width - spacing * CGFloat(Self.waveformBars - 1))
                               / CGFloat(Self.waveformBars))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<Self.waveformBars, id: \.self) { index in
                    let offset = Self.waveformBars - levels.count
                    let level = index >= offset ? levels[index - offset] : 0
                    Capsule()
                        .fill(Grimoire.primary.opacity(level > 0 ? 0.85 : 0.18))
                        .frame(width: barWidth,
                               height: max(2, proxy.size.height * CGFloat(level)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal, 30)
        .accessibilityHidden(true)
    }

    private var voiceMessage: String? {
        switch voice.status {
        case .unavailable(let reason), .failed(let reason): reason
        default: nil
        }
    }

    private func voiceMessageCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.slash")
                .foregroundStyle(Grimoire.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.grimoire(.footnote))
                .foregroundStyle(Grimoire.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Grimoire.secondarySoft,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try these ideas:")
                .font(.grimoire(.subhead, .emphasized))
                .foregroundStyle(Grimoire.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(ideas, id: \.self) { idea in
                    Button {
                        recall = idea
                    } label: {
                        Text(idea)
                            .font(.grimoire(.subhead))
                            .foregroundStyle(Grimoire.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Grimoire.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Grimoire.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(idea)
                    .accessibilityHint("Uses this as your description")
                }
            }
        }
    }

    private var companion: some View {
        HStack {
            Spacer()
            Image("Squirrel")
                .resizable()
                .scaledToFit()
                .frame(width: 88)
                .gentleFloat(amplitude: 3, duration: 3.4)
                .overlay(alignment: .topTrailing) {
                    MagicSparkle(size: 12, delay: 0.3).offset(x: 10, y: -4)
                }
            Spacer()
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private var searchBar: some View {
        NavigationLink(value: Route.matches(query: trimmedRecall)) {
            HStack(spacing: 8) {
                Text("Find Possible Matches")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .buttonStyle(GrimoirePrimaryButton())
        .disabled(trimmedRecall.isEmpty)
        .opacity(trimmedRecall.isEmpty ? 0.55 : 1)
        .simultaneousGesture(TapGesture().onEnded { voice.stop() })
        .accessibilityHint(trimmedRecall.isEmpty
                           ? "Describe what you remember first"
                           : "Looks through everything you've saved")
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func toggleDictation() async {
        if voice.isListening {
            voice.stop()
            return
        }
        focused = false
        recallBeforeDictation = trimmedRecall
        await voice.start()
    }
}
