import SwiftUI

struct RemoteSettingsView: View {
    @EnvironmentObject private var remote: RemoteInputManager
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: remote.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(remote.isConnected ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(remote.deviceName)
                            .font(.headline)
                        Text(remote.isConnected ? "События кнопок принимаются" : "Подключите пульт в Настройках iPhone → Bluetooth")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Принимать команды пульта", isOn: $remote.isEnabled)
                Toggle("Не показывать кнопки HUD при нажатии с пульта", isOn: $settingsStore.settings.keepControlsHiddenOnRemote)
                Button {
                    remote.refresh()
                } label: {
                    Label("Обновить статус подключения", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("Подключение")
            } footer: {
                Text("После первого сопряжения в настройках iPhone система сама восстанавливает связь с пультом.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Последняя распознанная кнопка")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(remote.lastInputDescription)
                        .font(.body.monospaced())
                    if let date = remote.lastInputDate {
                        Text(date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Проверка пульта")
            } footer: {
                Text("Нажмите любую кнопку на пульте прямо сейчас. Если её код появился выше — приложение её видит.")
            }

            Section {
                ForEach(RemoteAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(action.title, systemImage: action.symbol)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button {
                                if remote.capturingAction == action {
                                    remote.cancelCapture()
                                } else {
                                    remote.beginCapture(for: action)
                                }
                            } label: {
                                Text(remote.capturingAction == action ? "Отмена" : "Настроить")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .disabled(remote.capturingAction != nil && remote.capturingAction != action)
                        }
                        Text(assignedDescription(for: action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Назначение кнопок")
            } footer: {
                Text("Нажмите «Настроить», затем нажмите нужную кнопку на пульте.")
            }

            Section {
                Button("Сбросить назначения кнопок", role: .destructive) {
                    showResetConfirmation = true
                }
            } footer: {
                Text("Если пульт отправляет системные кнопки громкости или камеры, iOS может перехватывать их. Переключите режим работы на самом пульте или переназначьте кнопки выше.")
            }
        }
        .background(
            KeyPressCaptureView(remote: remote)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .navigationTitle("Пульт")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if let action = remote.capturingAction {
                VStack(spacing: 10) {
                    Text("Нажмите кнопку на пульте")
                        .font(.headline)
                    Text("Действие: \(action.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Отменить ожидание") {
                        remote.cancelCapture()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .alert(
            "Калибровка",
            isPresented: Binding(
                get: { remote.calibrationMessage != nil && remote.capturingAction == nil },
                set: { if !$0 { remote.calibrationMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(remote.calibrationMessage ?? "")
        }
        .confirmationDialog(
            "Сбросить назначения?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) { remote.resetMapping() }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear { remote.refresh() }
        .onDisappear { remote.cancelCapture() }
    }

    private func assignedDescription(for action: RemoteAction) -> String {
        let names = remote.mapping.inputs(for: action).map(\.displayName)
        return names.isEmpty ? "Не назначено" : names.joined(separator: ", ")
    }
}