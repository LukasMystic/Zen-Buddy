import Foundation
import Combine

struct BarkProfileTuning: Codable {
    var startOffset: Double
    var clipDuration: Double?
    var volume: Float
}

final class BarkSyncStore: ObservableObject {
    static let shared = BarkSyncStore()

    @Published private(set) var delaysByAction: [String: [Double]] = [:]
    @Published private(set) var profileByAction: [String: BarkProfileTuning] = [:]

    private let storageKey = "bark_sync_delays_v1"
    private let profileStorageKey = "bark_sync_profiles_v1"

    private init() {
        load()
        printCachedSettings()
    }

    func delays(for action: DogAction) -> [Double] {
        delaysByAction[action.storageKey] ?? []
    }

    func setDelay(for action: DogAction, at index: Int, value: Double) {
        var delays = delays(for: action)
        guard delays.indices.contains(index) else { return }
        delays[index] = max(0, min(15.0, value))
        delays.sort()
        delaysByAction[action.storageKey] = delays
        save()
    }

    func appendDelay(for action: DogAction) {
        var delays = delays(for: action)
        let next = (delays.max() ?? 0.1) + 0.2
        delays.append(min(next, 15.0))
        delays.sort()
        delaysByAction[action.storageKey] = delays
        save()
    }

    func removeLastDelay(for action: DogAction) {
        var delays = delays(for: action)
        guard !delays.isEmpty else { return }
        delays.removeLast()
        delaysByAction[action.storageKey] = delays
        save()
    }

    func reset(for action: DogAction) {
        delaysByAction[action.storageKey] = defaultDelays(for: action)
        profileByAction[action.storageKey] = defaultProfile(for: action)
        save()
    }

    func profile(for action: DogAction, base: BarkSFXProfile) -> BarkSFXProfile {
        let tuning = profileByAction[action.storageKey] ?? defaultProfile(for: action)
        return BarkSFXProfile(
            startOffset: tuning.startOffset,
            clipDuration: tuning.clipDuration,
            secondaryDelay: base.secondaryDelay,
            volume: tuning.volume
        )
    }

    func editableProfile(for action: DogAction) -> BarkProfileTuning {
        profileByAction[action.storageKey] ?? defaultProfile(for: action)
    }

    func setStartOffset(for action: DogAction, value: Double) {
        var tuning = editableProfile(for: action)
        tuning.startOffset = max(0, min(1.0, value))
        profileByAction[action.storageKey] = tuning
        save()
    }

    func setClipDuration(for action: DogAction, value: Double?) {
        var tuning = editableProfile(for: action)
        if let value {
            tuning.clipDuration = max(0.05, min(1.5, value))
        } else {
            tuning.clipDuration = nil
        }
        profileByAction[action.storageKey] = tuning
        save()
    }

    func setVolume(for action: DogAction, value: Float) {
        var tuning = editableProfile(for: action)
        tuning.volume = max(0.1, min(1.0, value))
        profileByAction[action.storageKey] = tuning
        save()
    }

    private func defaultDelays(for action: DogAction) -> [Double] {
        return []
    }

    private func defaultProfile(for action: DogAction) -> BarkProfileTuning {
        let base = action.barkProfile
        return BarkProfileTuning(
            startOffset: base.startOffset,
            clipDuration: base.clipDuration,
            volume: base.volume
        )
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: [Double]].self, from: data)
            delaysByAction = decoded
        } catch {
            print("Failed to load bark sync settings: \(error.localizedDescription)")
        }

        guard let profileData = UserDefaults.standard.data(forKey: profileStorageKey) else { return }
        do {
            let decodedProfiles = try JSONDecoder().decode([String: BarkProfileTuning].self, from: profileData)
            profileByAction = decodedProfiles
        } catch {
            print("Failed to load bark profile settings: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(delaysByAction)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save bark sync settings: \(error.localizedDescription)")
        }

        do {
            let profileData = try JSONEncoder().encode(profileByAction)
            UserDefaults.standard.set(profileData, forKey: profileStorageKey)
        } catch {
            print("Failed to save bark profile settings: \(error.localizedDescription)")
        }
    }

    func printCachedSettings() {
        print("\n=== CACHED BARK SETTINGS ===")
        print("\nDELAYS BY ACTION:")
        for action in DogAction.allCases {
            let delays = delaysByAction[action.storageKey] ?? []
            print("  \(action.title): \(delays)")
        }
        
        print("\nPROFILES BY ACTION:")
        for action in DogAction.allCases {
            if let profile = profileByAction[action.storageKey] {
                print("  \(action.title):")
                print("    - startOffset: \(profile.startOffset)")
                let clipDurStr = profile.clipDuration.map { String(format: "%.2f", $0) } ?? "nil"
                print("    - clipDuration: \(clipDurStr)")
                print("    - volume: \(profile.volume)")
            } else {
                print("  \(action.title): (not cached)")
            }
        }
        print("============================\n")
    }
}
