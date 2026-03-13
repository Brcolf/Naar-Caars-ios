//
//  AudioRecordingCoordinator.swift
//  NaarsCars
//
//  Manages AVAudioRecorder lifecycle, recording duration timer, and file management
//

import AVFoundation
import Observation

/// Coordinates audio recording for the message input bar.
/// Owns AVAudioRecorder, duration timer, and the recorded file URL.
@MainActor
@Observable
final class AudioRecordingCoordinator {

    struct RecordingResult {
        let url: URL
        let duration: TimeInterval
    }

    // MARK: - Observable State

    private(set) var isRecording = false
    private(set) var duration: TimeInterval = 0
    private(set) var hasRecordedFile = false

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?

    private let minimumDuration: TimeInterval = 1.0

    // MARK: - Actions

    func start() {
        Task {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = await AVAudioApplication.requestRecordPermission()
            } else {
                granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { result in
                        continuation.resume(returning: result)
                    }
                }
            }
            guard granted else { return }
            beginRecording()
        }
    }

    /// Stops recording and returns the result if duration >= minimum.
    /// Returns nil if recording was too short (file is cleaned up).
    func stop() -> RecordingResult? {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else { return nil }
        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil

        let finalDuration = Date().timeIntervalSince(recordingStartDate ?? Date())
        isRecording = false

        guard finalDuration >= minimumDuration else {
            cleanup(url: url)
            return nil
        }

        hasRecordedFile = true
        return RecordingResult(url: url, duration: finalDuration)
    }

    func cancel() {
        guard isRecording else { return }
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        if let url = recordingURL {
            cleanup(url: url)
        }
    }

    func clearRecordedFile() {
        hasRecordedFile = false
    }

    // MARK: - Private

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "voice_\(UUID().uuidString).m4a"
            let url = tempDir.appendingPathComponent(fileName)
            recordingURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            audioRecorder = recorder

            recordingStartDate = Date()
            duration = 0
            isRecording = true

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let start = self.recordingStartDate else { return }
                    self.duration = Date().timeIntervalSince(start)
                }
            }
        } catch {
            AppLogger.error("messaging", "Failed to begin audio recording: \(error)")
        }
    }

    private func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
        recordingStartDate = nil
        duration = 0
        hasRecordedFile = false
    }
}
