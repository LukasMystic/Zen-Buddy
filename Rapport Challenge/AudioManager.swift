import Foundation
import AVFoundation
import Combine

struct BarkSFXProfile {
    let startOffset: TimeInterval
    let clipDuration: TimeInterval?
    let secondaryDelay: TimeInterval?
    let volume: Float

    init(
        startOffset: TimeInterval = 0,
        clipDuration: TimeInterval? = nil,
        secondaryDelay: TimeInterval? = nil,
        volume: Float = 0.9
    ) {
        self.startOffset = startOffset
        self.clipDuration = clipDuration
        self.secondaryDelay = secondaryDelay
        self.volume = volume
    }
}

final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var activeSFXPlayers: [AVAudioPlayer] = []
    private var scheduledSFXItems: [DispatchWorkItem] = []
    private var fadeTimer: Timer?
    private let defaultMusicVolume: Float = 0.55
    private let fileName = "relaxing_bgm"
    private let fileExtension = "mp3"

    private init() {}

    func startIfNeeded() {
        if player == nil {
            configureSession()
            configurePlayer()
        }

        guard let player else {
            isPlaying = false
            return
        }

        if !player.isPlaying {
            player.volume = 0
            player.play()
        }
        fadeMusic(to: defaultMusicVolume, duration: 1.5)
        isPlaying = true
    }

    func pause() {
        guard player != nil else {
            isPlaying = false
            return
        }

        // Immediately update state so UI feels instantly responsive
        isPlaying = false 
        
        fadeMusic(to: 0, duration: 1.5) { [weak self] in
            self?.player?.pause()
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : startIfNeeded()
    }

    func playSFX(
        fromCandidates names: [String],
        delay: Double = 0,
        profile: BarkSFXProfile = BarkSFXProfile(),
        interruptExisting: Bool = true
    ) {
        guard !names.isEmpty else { return }

        if interruptExisting {
            stopAllSFX()
        }

        let playAction: () -> Void = { [weak self] in
            guard let self else { return }
            for name in names {
                if let url = self.resolveAudioURL(baseName: name) {
                    do {
                        let mainPlayer = try AVAudioPlayer(contentsOf: url)
                        let safeStart = max(0, min(profile.startOffset, mainPlayer.duration - 0.01))
                        mainPlayer.currentTime = safeStart
                        mainPlayer.volume = profile.volume
                        mainPlayer.prepareToPlay()
                        mainPlayer.play()
                        self.activeSFXPlayers.append(mainPlayer)

                        if let clipDuration = profile.clipDuration {
                            let stopTask = DispatchWorkItem { [weak self] in
                                mainPlayer.stop()
                                self?.activeSFXPlayers.removeAll { $0 === mainPlayer }
                            }
                            self.scheduledSFXItems.append(stopTask)
                            DispatchQueue.main.asyncAfter(deadline: .now() + clipDuration, execute: stopTask)
                        }

                        if let secondDelay = profile.secondaryDelay {
                            let secondTask = DispatchWorkItem { [weak self] in
                                guard let self else { return }
                                do {
                                    let second = try AVAudioPlayer(contentsOf: url)
                                    let secondStart = max(0, min(profile.startOffset, second.duration - 0.01))
                                    second.currentTime = secondStart
                                    second.volume = profile.volume * 0.92
                                    second.prepareToPlay()
                                    second.play()
                                    self.activeSFXPlayers.append(second)

                                    if let clipDuration = profile.clipDuration {
                                        let stopSecond = DispatchWorkItem { [weak self] in
                                            second.stop()
                                            self?.activeSFXPlayers.removeAll { $0 === second }
                                        }
                                        self.scheduledSFXItems.append(stopSecond)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + clipDuration, execute: stopSecond)
                                    }
                                } catch {
                                    print("Failed to play copied SFX \(name): \(error.localizedDescription)")
                                }
                            }
                            self.scheduledSFXItems.append(secondTask)
                            DispatchQueue.main.asyncAfter(deadline: .now() + secondDelay, execute: secondTask)
                        }

                        print("Playing SFX: \(name) (delay: \(delay)s, start: \(profile.startOffset)s)")
                        return
                    } catch {
                        print("Failed to play SFX \(name): \(error.localizedDescription)")
                    }
                }
            }
        }

        if delay > 0 {
            let delayedTask = DispatchWorkItem {
                playAction()
            }
            scheduledSFXItems.append(delayedTask)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: delayedTask)
        } else {
            playAction()
        }
    }

    func playSFXSequence(
        fromCandidates names: [String],
        delays: [Double],
        profile: BarkSFXProfile = BarkSFXProfile()
    ) {
        guard !names.isEmpty, !delays.isEmpty else { return }

        stopAllSFX()

        for delay in delays.sorted() {
            playSFX(
                fromCandidates: names,
                delay: max(0, delay),
                profile: profile,
                interruptExisting: false
            )
        }
    }

    func stopSFX() {
        stopAllSFX()
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func configurePlayer() {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            print("Missing music file: \(fileName).\(fileExtension) in app bundle")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = defaultMusicVolume
            player?.prepareToPlay()
        } catch {
            print("Failed to create audio player: \(error.localizedDescription)")
        }
    }

    private func resolveAudioURL(baseName: String) -> URL? {
        let extensions = ["wav", "mp3", "m4a"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: baseName, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func fadeMusic(to targetVolume: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard let player else {
            completion?()
            return
        }

        fadeTimer?.invalidate()

        if duration <= 0 {
            player.volume = targetVolume
            completion?()
            return
        }

        let steps = 20
        let startVolume = player.volume
        let delta = (targetVolume - startVolume) / Float(steps)
        let interval = duration / Double(steps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self, let player = self.player else {
                timer.invalidate()
                completion?()
                return
            }

            currentStep += 1
            let next = max(0, min(1, player.volume + delta))
            player.volume = next

            if currentStep >= steps {
                timer.invalidate()
                player.volume = targetVolume
                completion?()
            }
        }
    }

    private func stopAllSFX() {
        scheduledSFXItems.forEach { $0.cancel() }
        scheduledSFXItems.removeAll()

        activeSFXPlayers.forEach { $0.stop() }
        activeSFXPlayers.removeAll()
    }
}
