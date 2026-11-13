import Foundation
import UIKit

@MainActor
final class ScriptEditorViewModel: ObservableObject {
    @Published var title: String
    @Published var text: String
    @Published var errorMessage: String?

    let isNew: Bool
    private let original: PrompterScript?
    private let store: ScriptStore

    init(script: PrompterScript?, store: ScriptStore) {
        self.original = script
        self.store = store
        self.isNew = script == nil
        self.title = script?.title ?? ""
        self.text = script?.text ?? ""
    }

    var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var wordCount: Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    var hasUnsavedChanges: Bool {
        if let original {
            return title != original.title || text != original.text
        }
        return !title.isEmpty || !text.isEmpty
    }

    func replaceFromClipboard() {
        guard let clipboard = UIPasteboard.general.string,
              !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = ScriptStoreError.emptyClipboard.localizedDescription
            return
        }
        text = clipboard
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = "Из буфера обмена"
        }
    }

    @discardableResult
    func save() -> PrompterScript? {
        guard canSave else {
            errorMessage = "Добавьте текст сценария перед сохранением."
            return nil
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if var existing = original {
            existing.title = cleanTitle.isEmpty ? "Без названия" : cleanTitle
            existing.text = text
            store.update(existing)
            return existing
        } else {
            let script = PrompterScript(
                title: cleanTitle.isEmpty ? "Без названия" : cleanTitle,
                text: text
            )
            return store.add(script)
        }
    }
}