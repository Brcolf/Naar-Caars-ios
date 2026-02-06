//
//  MessageAudioPlayer.swift
//  NaarsCars
//
//  Audio playback manager for message voice notes
//

import SwiftUI
import AVFoundation
internal import Combine

@MainActor
final class MessageAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MessageAudioPlayer()
    
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentUrl: URL?
    
    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var cachedFiles: [URL: URL] = [:]
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    func togglePlayback(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        if isPlaying, currentUrl == url {
            pause()
        } else {
            Task { await play(url: url) }
        }
    }
    
    private func play(url: URL) async {
        stop()
        
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try? session.setActive(true)
            
            let playableUrl = try await resolvePlayableUrl(for: url)
            let audioPlayer = try AVAudioPlayer(contentsOf: playableUrl)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            
            player = audioPlayer
            currentUrl = url
            duration = audioPlayer.duration
            audioPlayer.play()
            
            isPlaying = true
            startProgressTimer()
        } catch {
            stop()
        }
    }
    
    private func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }
    
    private func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        duration = 0
        currentUrl = nil
        stopProgressTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            if player.duration > 0 {
                self.progress = player.currentTime / player.duration
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func resolvePlayableUrl(for url: URL) async throws -> URL {
        if url.isFileURL {
            return url
        }
        
        if let cached = cachedFiles[url] {
            return cached
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let fileName = "audio-\(abs(url.absoluteString.hashValue)).m4a"
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: fileUrl, options: .atomic)
        cachedFiles[url] = fileUrl
        return fileUrl
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        if type == .began {
            pause()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
