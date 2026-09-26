//  VoiceDictation.swift
//  Speaking a half-remembered idea instead of typing it.
//
//  ── ONE INPUT, NOT A SECOND SEARCH ─────────────────────────────────────────
//
//  This does not search. It fills the same field typing fills, and the reader
//  still presses Find Again. Speaking and typing are two ways to enter one
//  sentence, not two different jobs, so there is no "voice search" that runs a
//  different engine or returns different results.
//
//  ── WHICH RECOGNISER, AND WHY IT MATTERS HERE ──────────────────────────────
//
//  iOS 26 ships `SpeechTranscriber`, which is on-device by design — and covers
//  30 locales, none of them Indonesian. `SFSpeechRecognizer` covers 63 including
//  `id-ID`, but reports `supportsOnDeviceRecognition == false` for it: audio for
//  those languages is transcribed by Apple's servers.
//
//  That is a real conflict with an app that otherwise never sends anything
//  anywhere, so the choice is explicit rather than incidental:
//
//    • On-device is used wherever the locale supports it (English does).
//    • Where it does not, `allowsServerTranscription` decides. It ships `true`,
//      because a reader who speaks Indonesian would otherwise get a microphone
//      that never works — but `isOnDevice` is published so the UI can say what
//      is happening, and set it to `false` for strictly-offline builds.
//
//  Typing remains reachable in every state. Nothing here is required to search.

import Foundation
import Speech
import AVFoundation
import Observation
import OSLog

@MainActor
@Observable
final class VoiceDictation {

    /// Ships `true`. Set `false` to refuse any transcription that would leave
    /// the device — voice then works only in locales with on-device support.
    static let allowsServerTranscription = true

    enum Status: Equatable {
        case idle
        case preparing
        case listening
        /// Never recoverable here: no recogniser for this language, or the user
        /// declined permission and must change it in Settings.
        case unavailable(String)
        /// Worth another try — the audio session was interrupted, say.
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// What has been heard so far. Partial results arrive continuously, so this
    /// changes while the reader is still speaking.
    private(set) var transcript = ""

    /// 0…1, driven by the microphone. Drives the listening animation, so it is
    /// visibly reacting to the reader's voice rather than to a timer.
    private(set) var level: Double = 0

    /// False when this language is transcribed by Apple rather than on device.
    /// Surfaced in the UI; it is not a failure, just a fact worth stating.
    private(set) var isOnDevice = true

    var isListening: Bool { status == .listening }

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = .current) {
        // The reader's own language first, English as the fallback: a recogniser
        // for an unsupported locale is nil rather than an error at start time.
        let preferred = SFSpeechRecognizer(locale: locale)
        recognizer = preferred ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        isOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
    }

    /// True where a microphone button is worth showing at all.
    static var isSupported: Bool {
        SFSpeechRecognizer(locale: .current) != nil
            || SFSpeechRecognizer(locale: Locale(identifier: "en-US")) != nil
    }

    // MARK: - Lifecycle

    func start() async {
        guard status != .listening else { return }
        transcript = ""
        level = 0
        status = .preparing

        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Speech recognition isn't available right now.")
            return
        }

        let onDevice = recognizer.supportsOnDeviceRecognition
        isOnDevice = onDevice
        guard onDevice || Self.allowsServerTranscription else {
            status = .unavailable("This language can only be transcribed by Apple, and that is turned off in this build. You can type instead.")
            return
        }

        guard await requestPermissions() else { return }

        do {
            try beginCapture(on: recognizer, onDevice: onDevice)
            status = .listening
        } catch {
            Logger.voice.error("Dictation failed to start: \(String(describing: error))")
            stop()
            status = .failed("The microphone didn't start. Try again, or type instead.")
        }
    }

    /// Ends the session and keeps whatever was heard.
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
        if status == .listening || status == .preparing { status = .idle }

        // Handing the session back matters: leaving it active leaves the app
        // holding the microphone, and on a real device that is audible to the
        // rest of the system.
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        stop()
        transcript = ""
        status = .idle
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            status = .unavailable("Speech recognition is off for ReTREEve. You can turn it on in Settings, or type instead.")
            return false
        }

        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            status = .unavailable("Microphone access is off for ReTREEve. You can turn it on in Settings, or type instead.")
            return false
        }
        return true
    }

    // MARK: - Capture

    private func beginCapture(on recognizer: SFSpeechRecognizer, onDevice: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        // A search phrase, not a document: this hints the recogniser to settle
        // quickly rather than wait for a long dictation to finish.
        request.taskHint = .search
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let peak = Self.peakLevel(of: buffer)
            Task { @MainActor [weak self] in self?.level = peak }
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    // A recogniser error after speech has been heard is the
                    // normal end of a phrase, not a failure worth reporting.
                    self.stop()
                }
            }
        }
    }

    /// Peak amplitude of one buffer, compressed into something an animation can
    /// use. Peak rather than average: a meter driven by the average barely moves
    /// on speech, which makes the app look like it stopped listening.
    private nonisolated static func peakLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var peak: Float = 0
        for index in 0..<count { peak = max(peak, abs(channel[index])) }
        // Speech rarely reaches full scale, so the useful range is squeezed into
        // the bottom of it; the square root opens it back up.
        return min(1, Double(peak).squareRoot())
    }
}

extension Logger {
    nonisolated static let voice = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReTREEve",
        category: "voice")
}
