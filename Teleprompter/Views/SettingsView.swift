import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var remote: RemoteInputManager
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    valueSlider(
                        title: "Размер шрифта",
                        value: $store.settings.fontSize,
                        range: PrompterSettings.fontRange,
                        step: 1,
                        unit: "пт"
                    )
                    valueSlider(
                        title: "Межстрочный интервал",
                        value: $store.settings.lineSpacing,
                        range: PrompterSettings.lineSpacingRange,
                        step: 1,
                        unit: "пт"
                    )
                    Picker("Выравнивание", selection: $store.settings.textAlignment) {
                        ForEach(PrompterTextAlignment.allCases) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }
                    ColorPicker("Цвет текста", selection: store.colorBinding(for: \.textColor), supportsOpacity: false)
                    ColorPicker("Цвет фона", selection: store.colorBinding(for: \.backgroundColor), supportsOpacity: false)
                } header: {
                    Text("Текст")
                } footer: {
                    Text("Настройки применяются ко всем сценариям и сохраняются автоматически.")
                }

                Section("Прокрутка") {
                    valueSlider(
                        title: "Скорость",
                        value: $store.settings.speed,
                        range: PrompterSettings.speedRange,
                        step: 5,
                        unit: "пт/с"
                    )
                    Stepper(
                        "Отсчёт перед стартом: \(store.settings.countdownSeconds) с",
                        value: $store.settings.countdownSeconds,
                        in: 0...10
                    )
                    Toggle("Метка строки чтения", isOn: $store.settings.showReadingGuide)
                    if store.settings.showReadingGuide {
                        valueSlider(
                            title: "Положение метки",
                            value: $store.settings.readingPosition,
                            range: PrompterSettings.readingPositionRange,
                            step: 0.01,
                            unit: "%"
                        )
                    }
                }

                Section {
                    Toggle("Зеркалировать текст", isOn: $store.settings.mirrored)
                } header: {
                    Text("Зеркало")
                } footer: {
                    Text("Горизонтальное отражение для стеклянного телесуфлёра. Работает и во время прокрутки; состояние сохраняется.")
                }

                Section("Экран и отклик") {
                    Picker("Ориентация экрана", selection: $store.settings.orientationLock) {
                        ForEach(ScreenOrientationLock.allCases) { lock in
                            Text(lock.title).tag(lock)
                        }
                    }
                    Toggle("Виброотклик при управлении", isOn: $store.settings.hapticFeedback)
                    Picker("Тема интерфейса", selection: $store.settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    NavigationLink {
                        RemoteSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Bluetooth-пульт")
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(remote.isConnected ? Color.green : Color.secondary)
                                        .frame(width: 8, height: 8)
                                    Text(remote.isConnected ? "Подключён (\(remote.deviceName))" : "Не подключён")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Управление")
                } footer: {
                    Text("Подключение, проверка кнопок и переназначение действий.")
                }

                Section {
                    Button("Сбросить настройки суфлёра", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Настройки")
            .confirmationDialog(
                "Сбросить настройки?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Сбросить", role: .destructive) {
                    store.resetToDefaults()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Шрифт, скорость, цвета, зеркало и отсчёт вернутся к значениям по умолчанию. Сценарии и кнопки пульта не изменятся.")
            }
        }
    }

    @ViewBuilder
    private func valueSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(displayValue(value.wrappedValue, unit: unit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }

    private func displayValue(_ value: Double, unit: String) -> String {
        if unit == "%" {
            return "\(Int(value * 100))%"
        }
        return "\(Int(value)) \(unit)"
    }
}