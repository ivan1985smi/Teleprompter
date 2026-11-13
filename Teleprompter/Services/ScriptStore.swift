import Foundation
import UIKit

enum ScriptStoreError: LocalizedError {
    case emptyClipboard
    case emptyFile
    case unreadableText
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "В буфере обмена нет текста. Скопируйте сценарий и попробуйте ещё раз."
        case .emptyFile:
            return "Выбранный файл пуст."
        case .unreadableText:
            return "Не удалось распознать кодировку файла. Сохраните его в UTF-8 или UTF-16 с расширением .txt."
        case .fileTooLarge:
            return "Файл слишком большой. Максимальный размер текстового сценария — 20 МБ."
        }
    }
}

@MainActor
final class ScriptStore: ObservableObject {
    @Published private(set) var scripts: [PrompterScript] = []
    @Published var errorMessage: String?

    private let fileURL: URL
    private let defaults: UserDefaults
    private let seededKey = "scripts.seeded.v1"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("Teleprompter/scripts.json", isDirectory: false)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    func script(id: UUID) -> PrompterScript? {
        scripts.first { $0.id == id }
    }

    @discardableResult
    func add(_ script: PrompterScript) -> PrompterScript {
        scripts.append(script)
        sort()
        persist()
        return script
    }

    func update(_ script: PrompterScript) {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        guard scripts[index] != script else { return }
        var updated = script
        updated.updatedAt = .now
        scripts[index] = updated
        sort()
        persist()
    }

    func delete(id: UUID) {
        scripts.removeAll { $0.id == id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { scripts[$0].id }
        scripts.removeAll { ids.contains($0.id) }
        persist()
    }

    @discardableResult
    func duplicate(id: UUID) -> PrompterScript? {
        guard let original = script(id: id) else { return nil }
        let copy = PrompterScript(
            title: original.displayTitle + " — копия",
            text: original.text
        )
        return add(copy)
    }

    @discardableResult
    func createFromClipboard() throws -> PrompterScript {
        guard let rawText = UIPasteboard.general.string else {
            throw ScriptStoreError.emptyClipboard
        }
        let cleaned = Self.cleanImportedText(rawText)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScriptStoreError.emptyClipboard
        }
        return add(PrompterScript(title: "Из буфера обмена", text: cleaned))
    }

    @discardableResult
    func importText(from url: URL) throws -> PrompterScript {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? NSNumber, size.intValue > 20 * 1024 * 1024 {
            throw ScriptStoreError.fileTooLarge
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty else { throw ScriptStoreError.emptyFile }
        guard data.count <= 20 * 1024 * 1024 else { throw ScriptStoreError.fileTooLarge }

        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1251]
        guard let decoded = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first else {
            throw ScriptStoreError.unreadableText
        }
        let cleaned = Self.cleanImportedText(decoded)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScriptStoreError.emptyFile
        }

        let title = url.deletingPathExtension().lastPathComponent
        return add(PrompterScript(title: title, text: cleaned))
    }

    func exportTemporaryFile(for script: PrompterScript) -> URL? {
        let safeName = script.displayTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).txt")
        do {
            try script.text.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    private static func cleanImportedText(_ raw: String) -> String {
        var result = raw
        if result.hasPrefix("\u{FEFF}") {
            result.removeFirst()
        }
        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func load() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                scripts = try decoder.decode([PrompterScript].self, from: data)
                sort()
            } else if !defaults.bool(forKey: seededKey) {
                scripts = [.sample]
                defaults.set(true, forKey: seededKey)
                persist()
            }
        } catch {
            errorMessage = "Не удалось открыть библиотеку: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(scripts)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            errorMessage = "Не удалось сохранить сценарии: \(error.localizedDescription)"
        }
    }

    private func sort() {
        scripts.sort { $0.updatedAt > $1.updatedAt }
    }
}