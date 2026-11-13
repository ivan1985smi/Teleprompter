import SwiftUI
import UniformTypeIdentifiers

struct EditorSelection: Identifiable {
    let id = UUID()
    let script: PrompterScript?
}

struct LibraryView: View {
    @EnvironmentObject private var scripts: ScriptStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var remote: RemoteInputManager

    @State private var editorSelection: EditorSelection?
    @State private var playerScript: PrompterScript?
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var searchText = ""

    private var filteredScripts: [PrompterScript] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return scripts.scripts }
        let query = searchText.lowercased()
        return scripts.scripts.filter {
            $0.displayTitle.lowercased().contains(query) || $0.text.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredScripts) { script in
                    ScriptRow(script: script)
                        .contentShape(Rectangle())
                        .onTapGesture { playerScript = script }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                scripts.delete(id: script.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            Button {
                                editorSelection = EditorSelection(script: script)
                            } label: {
                                Label("Править", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                playerScript = script
                            } label: {
                                Label("Читать", systemImage: "play.fill")
                            }
                            Button {
                                editorSelection = EditorSelection(script: script)
                            } label: {
                                Label("Редактировать", systemImage: "pencil")
                            }
                            Button {
                                scripts.duplicate(id: script.id)
                            } label: {
                                Label("Дублировать", systemImage: "plus.square.on.square")
                            }
                            if let exportURL = scripts.exportTemporaryFile(for: script) {
                                ShareLink(item: exportURL) {
                                    Label("Экспортировать TXT", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button(role: .destructive) {
                                scripts.delete(id: script.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteFiltered)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Суфлёр")
            .searchable(text: $searchText, prompt: "Поиск по сценариям")
            .overlay {
                if filteredScripts.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "Нет сценариев" : "Ничего не найдено")
                            .font(.headline)
                        if searchText.isEmpty {
                            Text("Создайте новый сценарий, вставьте текст из буфера или импортируйте файл .txt.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            HStack(spacing: 12) {
                                Button("Создать") {
                                    editorSelection = EditorSelection(script: nil)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Импорт TXT") {
                                    showFileImporter = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            editorSelection = EditorSelection(script: nil)
                        } label: {
                            Label("Новый сценарий", systemImage: "square.and.pencil")
                        }
                        Button {
                            importClipboard()
                        } label: {
                            Label("Из буфера обмена", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Из файла TXT", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Добавить сценарий")
                }
            }
            .sheet(item: $editorSelection) { selection in
                ScriptEditorView(script: selection.script, store: scripts)
            }
            .fullScreenCover(item: $playerScript) { script in
                PrompterScreen(script: script, settingsStore: settings, remote: remote)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(
                "Импорт не удался",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func deleteFiltered(at offsets: IndexSet) {
        let ids = offsets.map { filteredScripts[$0].id }
        for id in ids { scripts.delete(id: id) }
    }

    private func importClipboard() {
        do {
            let script = try scripts.createFromClipboard()
            editorSelection = EditorSelection(script: script)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let script = try scripts.importText(from: url)
            editorSelection = EditorSelection(script: script)
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct ScriptRow: View {
    let script: PrompterScript

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.title3)
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(script.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(script.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("\(script.wordCount) слов")
                    Text("•")
                    Text("~\(script.estimatedReadingTimeFormatted)")
                    Text("•")
                    Text(script.updatedAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть сценарий в телесуфлёре")
    }
}