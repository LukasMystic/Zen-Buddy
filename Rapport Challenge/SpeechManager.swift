import Foundation
import Speech
import AVFoundation
import Combine

class SpeechManager: ObservableObject {
    static let shared = SpeechManager()
    
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var isListening = false
    @Published var recognizedCommand: String = ""
    
    var onCommandRecognized: ((DogAction) -> Void)?
    var dogName: String = "Buddy"
    
    func toggleListening(name: String) {
        self.dogName = name.lowercased()
        if isListening {
            stopListening()
        } else {
            requestPermissions()
        }
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    // We must ask for Mic permission as well
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        DispatchQueue.main.async {
                            if granted {
                                self?.startListening()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func startListening() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard !self.audioEngine.isRunning else { return }
            
            let audioSession = AVAudioSession.sharedInstance()
            do {
                // Must use playAndRecord to allow microphone and speaker output simultaneously
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print("Audio session configuration failed: \(error)")
                return
            }
            
            self.request = SFSpeechAudioBufferRecognitionRequest()
            guard let request = self.request else { return }
            request.shouldReportPartialResults = true
            
            let node = self.audioEngine.inputNode
            let recordingFormat = node.outputFormat(forBus: 0)
            
            node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }
            
            self.audioEngine.prepare()
            do {
                try self.audioEngine.start()
                DispatchQueue.main.async {
                    self.isListening = true
                    self.recognizedCommand = "Listening..."
                }
            } catch {
                print("Audio engine start failed: \(error)")
                return
            }
            
            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result {
                    let transcription = result.bestTranscription.formattedString.lowercased()
                    DispatchQueue.main.async {
                        self.recognizedCommand = transcription
                        self.processCommand(transcription)
                    }
                }
                
                if error != nil || (result?.isFinal ?? false) {
                    self.stopListening()
                }
            }
        }
    }
    
    func stopListening() {
        // Run audio tear down on background thread to prevent UI/RealityKit frame drops!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.audioEngine.stop()
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.request?.endAudio()
            self.recognitionTask?.cancel()
            
            DispatchQueue.main.async {
                self.request = nil
                self.recognitionTask = nil
                self.isListening = false
                // don't wipe recognizedCommand yet, we use it for UI
            }
            
            // Reset category back to ambient for normal app playback
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? audioSession.setActive(true)
        }
    }
    
    private func processCommand(_ text: String) {
        
        
        guard text.contains(dogName) else { return }
        
        var detectedAction: DogAction? = nil
        
        if text.contains("sit") {
            detectedAction = .sitting
        } else if text.contains("roll over") || text.contains("rollover") {
            detectedAction = .rollover
        } else if text.contains("shake") {
            detectedAction = .shake
        } else if text.contains("play dead") || text.contains("bang") || text.contains("shoot") {
            detectedAction = .playDead
        } else if text.contains("stand") || text.contains("up") {
            detectedAction = .standing
        }
        
        if let action = detectedAction {
            // Execute on main thread
            DispatchQueue.main.async {
                self.onCommandRecognized?(action)
                // Stop to require a fresh button press or just reset?
                // Let's stop listening after successful command
                self.stopListening()
                self.recognizedCommand = "Good boy, \(self.dogName.capitalized)!"
                
                // Clear the message after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !self.isListening {
                        self.recognizedCommand = ""
                    }
                }
            }
        }
    }
}
