import SwiftUI

struct ScriptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ScriptEditorViewModel
    @State private var showDiscardConfirmation = false

    @MainActor
    init(script: PrompterScript?, store: ScriptStore) {
        _model = StateObject(wrappedValue: ScriptEditorViewModel(script: script, store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Название сценария", text: $model.title)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                Divider()

                TextEditor(text: $model.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                    .padding(.horizontal, 12)
                    .overlay(alignment: .topLeading) {
                        if model.text.isEmpty {
                            Text("Введите или вставьте текст сценария…")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }

                Divider()

                HStack {
                    Text("\(model.wordCount) слов")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button {
                            model.replaceFromClipboard()
                        } label: {
                            Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                        }
                        Button(role: .destructive) {
                            model.text = ""
                        } label: {
                            Label("Очистить текст", systemImage: "trash")
                        }
                    } label: {
                        Label("Текст", systemImage: "ellipsis.circle")
                            .font(.footnote)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
            }
            .navigationTitle(model.isNew ? "Новый сценарий" : "Редактор")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        if model.hasUnsavedChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        if model.save() != nil { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!model.canSave)
                }
            }
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .confirmationDialog(
                "Отменить изменения?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Отменить изменения", role: .destructive) { dismiss() }
                Button("Продолжить редактирование", role: .cancel) {}
            }
        }
    }
}
