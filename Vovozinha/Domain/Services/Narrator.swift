import Foundation
import AVFoundation
import Observation
import os

private let narratorLog = Logger(subsystem: "app.vovozinha", category: "Narrator")

/// 100% offline narration via system `AVSpeechSynthesizer`.
/// Audiobook mode speaks **one page at a time**, updates `currentPageIndex`, and pauses between pages.
///
/// Audio session configure/activate runs **off the main actor** to avoid UI hangs
/// (`AVAudioSession` / `SessionCore` main-thread warnings).
@MainActor
@Observable
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var speakTask: Task<Void, Never>?
    private var speakGeneration = 0

    /// Utterances still playing for the current page (used to know when the page is done).
    private var remainingUtterancesForPage = 0
    private var pageFinishedContinuation: CheckedContinuation<Void, Never>?

    private(set) var isSpeaking = false
    /// Absolute story page index currently being narrated (drives TabView).
    private(set) var currentPageIndex: Int?
    private(set) var activeVoiceName: String?
    private(set) var activeVoiceQualityRank: Int = 0
    /// True while multi-page audiobook is running.
    private(set) var isAudiobookMode = false

    var rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.9
    var pitchMultiplier: Float = 1.04
    var speechLanguage: String = AppLanguage.fromSystem().speechLanguage
    var preferredVoiceIdentifier: String? = AppSettings.preferredVoiceIdentifier
    /// Pause between sentences within a page.
    var sentencePause: TimeInterval = 0.18
    /// Pause after a page finishes before advancing to the next (audiobook).
    var pageGap: TimeInterval = 0.9

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func reloadVoicePreference() {
        preferredVoiceIdentifier = AppSettings.preferredVoiceIdentifier
    }

    func speak(text: String, pageIndex: Int? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            narratorLog.warning("speak skipped: empty text")
            isSpeaking = false
            currentPageIndex = nil
            isAudiobookMode = false
            return
        }
        let item = PageSpeech(index: pageIndex ?? 0, text: trimmed)
        startPlayback(pages: [item], audiobook: false)
    }

    /// Full-story narration. `pages` is the full ordered list; `startAt` is the first index to read.
    func speakStory(pages: [String], startAt: Int = 0) {
        guard startAt < pages.count else { return }
        var items: [PageSpeech] = []
        for index in startAt..<pages.count {
            let text = pages[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            items.append(PageSpeech(index: index, text: text))
        }
        guard !items.isEmpty else {
            narratorLog.warning("speakStory skipped: no text")
            isSpeaking = false
            currentPageIndex = nil
            isAudiobookMode = false
            return
        }
        startPlayback(pages: items, audiobook: true)
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        speakGeneration += 1
        finishPageWaitIfNeeded()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        remainingUtterancesForPage = 0
        isSpeaking = false
        currentPageIndex = nil
        isAudiobookMode = false
    }

    func deactivateAudioSession() {
        stop()
        Task {
            await AudioSessionWorker.deactivate()
        }
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Sequential playback

    private struct PageSpeech {
        let index: Int
        let text: String
    }

    private func startPlayback(pages: [PageSpeech], audiobook: Bool) {
        speakTask?.cancel()
        speakGeneration += 1
        let generation = speakGeneration
        reloadVoicePreference()

        isAudiobookMode = audiobook
        isSpeaking = true
        currentPageIndex = pages.first?.index

        speakTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if self.synthesizer.isSpeaking || self.synthesizer.isPaused {
                self.synthesizer.stopSpeaking(at: .immediate)
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard !Task.isCancelled, generation == self.speakGeneration else { return }

            // Configure/activate off the main actor (avoids SessionCore / AVAudioSession UI warnings).
            let sessionOK = await AudioSessionWorker.activate()
            guard !Task.isCancelled, generation == self.speakGeneration else { return }
            if !sessionOK {
                narratorLog.error("audio session not active — speech may be silent")
            }
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, generation == self.speakGeneration else { return }

            let voice = self.resolveVoice()
            self.activeVoiceName = voice?.name
            self.activeVoiceQualityRank = voice.map { VoiceCatalog.qualityRank(of: $0) } ?? 0

            narratorLog.info(
                "playback pages=\(pages.count) audiobook=\(audiobook) lang=\(self.speechLanguage, privacy: .public) voice=\(voice?.name ?? "?", privacy: .public) pageGap=\(self.pageGap)"
            )

            for (offset, page) in pages.enumerated() {
                guard !Task.isCancelled, generation == self.speakGeneration else { return }

                self.currentPageIndex = page.index
                self.isSpeaking = true

                await self.speakOnePage(page.text, voice: voice, generation: generation)
                guard !Task.isCancelled, generation == self.speakGeneration else { return }

                if audiobook, offset < pages.count - 1 {
                    let gapNs = UInt64(max(0.2, self.pageGap) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: gapNs)
                }
            }

            guard generation == self.speakGeneration else { return }
            self.isSpeaking = false
            self.isAudiobookMode = false
            narratorLog.info("playback finished")
        }
    }

    /// Speak a single page and wait until all its utterances finish (or cancel).
    private func speakOnePage(_ text: String, voice: AVSpeechSynthesisVoice?, generation: Int) async {
        let chunks = speechUnits(for: text)
        guard !chunks.isEmpty else { return }

        finishPageWaitIfNeeded()
        remainingUtterancesForPage = chunks.count

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.pageFinishedContinuation = continuation

            for (i, chunk) in chunks.enumerated() {
                let utterance = makeUtterance(chunk, voice: voice)
                if i < chunks.count - 1 {
                    utterance.postUtteranceDelay = sentencePause
                } else {
                    utterance.postUtteranceDelay = 0.05
                }
                synthesizer.speak(utterance)
            }

            // Safety: if synthesizer never starts (sim), don't hang forever.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard let self else { return }
                guard generation == self.speakGeneration else { return }
                if self.pageFinishedContinuation != nil {
                    narratorLog.warning("page speech timed out — continuing")
                    self.remainingUtterancesForPage = 0
                    self.finishPageWaitIfNeeded()
                }
            }
        }
    }

    private func finishPageWaitIfNeeded() {
        if let cont = pageFinishedContinuation {
            pageFinishedContinuation = nil
            cont.resume()
        }
    }

    private func noteUtteranceFinished() {
        remainingUtterancesForPage = max(0, remainingUtterancesForPage - 1)
        if remainingUtterancesForPage == 0 {
            finishPageWaitIfNeeded()
        }
        if !synthesizer.isSpeaking && remainingUtterancesForPage == 0 {
            if !isAudiobookMode {
                isSpeaking = false
            }
        }
    }

    // MARK: - Voice helpers

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        VoiceCatalog.resolveVoice(
            languageCode: speechLanguage,
            preferredIdentifier: preferredVoiceIdentifier
        )
    }

    private func makeUtterance(_ text: String, voice: AVSpeechSynthesisVoice?) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = clampedRate(rate)
        utterance.pitchMultiplier = min(max(pitchMultiplier, 0.5), 2.0)
        utterance.volume = 1.0
        utterance.prefersAssistiveTechnologySettings = false
        utterance.preUtteranceDelay = 0
        return utterance
    }

    private func clampedRate(_ value: Float) -> Float {
        let lo = max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 0.7)
        let hi = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.1)
        return min(max(value, lo), hi)
    }

    private func speechUnits(for text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let words = trimmed.split(whereSeparator: \.isWhitespace).count
        if words <= 18 {
            return [trimmed]
        }

        var chunks: [String] = []
        var current = ""
        for scalar in trimmed.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if ".!?…".unicodeScalars.contains(scalar) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { chunks.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks.isEmpty ? [trimmed] : chunks
    }

    // MARK: - Delegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.noteUtteranceFinished()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.remainingUtterancesForPage = 0
            self.finishPageWaitIfNeeded()
            if !self.synthesizer.isSpeaking {
                self.isSpeaking = false
            }
        }
    }
}

// MARK: - Off-main audio session

/// Configures `AVAudioSession` away from the main actor so activation never blocks the UI.
private enum AudioSessionWorker {
    static func activate() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playback, mode: .default, options: [.duckOthers])
                    try session.setActive(true)
                    continuation.resume(returning: true)
                } catch {
                    do {
                        try session.setCategory(.playback, options: [.duckOthers])
                        try session.setActive(true)
                        continuation.resume(returning: true)
                    } catch {
                        narratorLog.error("audio session activate failed: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    static func deactivate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                } catch {
                    narratorLog.debug("audio session deactivate: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }
}
