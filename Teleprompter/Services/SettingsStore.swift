import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: PrompterSettings {
        didSet {
            guard settings != oldValue else { return }
            var normalized = settings
            normalized.normalize()
            if normalized != settings {
                settings = normalized
                return
            }
            persist()
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, storageKey: String = "prompter.settings.v1") {
        self.defaults = defaults
        self.storageKey = storageKey

        var loaded = PrompterSettings()
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(PrompterSettings.self, from: data) {
            loaded = decoded
        }
        loaded.normalize()
        self.settings = loaded
    }

    func colorBinding(for keyPath: WritableKeyPath<PrompterSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { self.settings[keyPath: keyPath].color },
            set: { self.settings[keyPath: keyPath] = RGBAColor($0) }
        )
    }

    func resetToDefaults() {
        settings = PrompterSettings()
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}