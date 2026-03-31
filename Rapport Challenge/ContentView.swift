import SwiftUI
import Combine
import Foundation

struct ContentView: View {
    @StateObject var vm = DogVM()
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var speechManager = SpeechManager.shared
    @State private var flashScreen = false
    @State private var musicBump = false
    @State private var cameraBump = false
    
    var body: some View {
        ZStack {
            // AR Layer
            ARScreen(vm: vm)
                .ignoresSafeArea()
                .transition(.opacity)
                .opacity(1.0)
                .animation(.easeInOut(duration: 0.8), value: vm.selectedAction)
                
            // Top Controls Layer
            VStack {
                HStack {
                    // Top Left: Music Toggle
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            audioManager.togglePlayback()
                        }
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                            musicBump = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                musicBump = false
                            }
                        }
                    }) {
                        Image(systemName: audioManager.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.title3)
                            .foregroundColor(audioManager.isPlaying ? .white : .white.opacity(0.6))
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .scaleEffect(musicBump ? 1.15 : 1.0)
                            .rotationEffect(.degrees(musicBump ? 10 : 0))
                            .accessibilityLabel(audioManager.isPlaying ? "Mute Music" : "Play Music")
                    }

                    Spacer()

                    // Top Right: Preferences
                    Button(action: {
                        vm.showPreferences = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .accessibilityLabel("Settings")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
            }

            // Bottom Controls Layer
            VStack {
                Spacer()

                // Clean, minimalist voice feedback glass pill
                if speechManager.isListening {
                    Text(speechManager.recognizedCommand.isEmpty ? "Listening..." : speechManager.recognizedCommand.capitalized)
                        .font(.headline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.bottom, 24)
                        .animation(.easeInOut, value: speechManager.recognizedCommand)
                        .transition(.opacity)
                }

                HStack(spacing: 40) {
                    // Enlarged Mic button
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        speechManager.toggleListening(name: vm.dogName)
                    }) {
                        Image(systemName: speechManager.isListening ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundColor(speechManager.isListening ? .mint : .white)
                            .frame(width: 80, height: 80)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                            .shadow(color: speechManager.isListening ? Color.mint.opacity(0.4) : Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
                            .scaleEffect(speechManager.isListening ? 1.05 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: speechManager.isListening)
                    }
                    .accessibilityLabel("Voice Command")

                    // Enlarged Photo button
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        vm.takeSnapshot = true
                        
                        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.5, blendDuration: 0.2)) {
                            cameraBump = true
                        }
                        
                        // Flash effect
                        withAnimation(.easeOut(duration: 0.05)) { flashScreen = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeIn(duration: 0.3)) { 
                                flashScreen = false 
                                cameraBump = false
                            }
                        }
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                            .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
                            .scaleEffect(cameraBump ? 0.85 : 1.0)
                    }
                    .accessibilityLabel("Take Photo")
                }
                .padding(.bottom, 60)
            }
            
            // Camera Flash Overlay
            if flashScreen {
                Color.white
                    .ignoresSafeArea()
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: vm.selectedAction)
        .onAppear {
            speechManager.onCommandRecognized = { action in
                withAnimation(.easeInOut(duration: 0.8)) {
                    vm.selectedAction = action
                }
            }
        }
        .sheet(isPresented: $vm.showPreferences) {
            PreferencesView(vm: vm)
                .presentationDetents([.fraction(0.5)])
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(30)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var vm: DogVM
    
    // Preset colors for the dog's tint
    let tintOptions: [(String, UIColor)] = [
        ("Original", .white),
        ("Golden", UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1.0)),
        ("Brown", UIColor(red: 0.55, green: 0.27, blue: 0.07, alpha: 1.0)),
        ("Dark", UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)),
        ("Gray", UIColor(white: 0.6, alpha: 1.0)),
        ("Auburn", UIColor(red: 0.6, green: 0.2, blue: 0.1, alpha: 1.0)),
        ("Silver", UIColor(red: 0.75, green: 0.75, blue: 0.8, alpha: 1.0)),
        ("Black", UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Dog Identity").font(.subheadline.weight(.semibold)).foregroundColor(.primary)) {
                    TextField("Name", text: $vm.dogName)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 4)
                }
                .listRowBackground(Color(UIColor.systemBackground).opacity(0.6))
                
                Section(header: Text("Coat Tint / Texture").font(.subheadline.weight(.semibold)).foregroundColor(.primary)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(tintOptions, id: \.0) { option in
                                VStack {
                                    Button(action: {
                                        vm.dogTint = option.1
                                        vm.applyTint = true
                                    }) {
                                        Circle()
                                            .fill(Color(option.1))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: vm.dogTint == option.1 ? 3 : 0)
                                                    .padding(-2)
                                            )
                                            .shadow(color: Color.black.opacity(0.15), radius: 4)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    Text(option.0)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }
                .listRowBackground(Color(UIColor.systemBackground).opacity(0.6))
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Preferences")
            .navigationBarItems(trailing: Button("Done") {
                vm.showPreferences = false
            }.font(.headline))
        }
        .accentColor(.primary)
    }
}

// Unused but kept for compatibility
struct BarkTunerPanel: View {
    @EnvironmentObject var barkSyncStore: BarkSyncStore
    let action: DogAction

    var body: some View {
        EmptyView()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct DogCommandButton: View {
    var title: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(.ultraThinMaterial)
                .cornerRadius(15)
        }
    }
}
