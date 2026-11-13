import SwiftUI

struct PrompterScreen: View {
    @StateObject private var model: PrompterViewModel
    let remote: RemoteInputManager
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(script: PrompterScript, settingsStore: SettingsStore, remote: RemoteInputManager) {
        self.remote = remote
        _model = StateObject(
            wrappedValue: PrompterViewModel(
                script: script,
                settingsStore: settingsStore,
                remote: remote
            )
        )
    }

    var body: some View {
        PrompterView(model: model, remote: remote) {
            dismiss()
        }
    }
}

struct PrompterView: View {
    @ObservedObject var model: PrompterViewModel
    let remote: RemoteInputManager
    let onClose: () -> Void

    @State private var scrubValue: Double?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        ZStack {
            KeyPressCaptureView(remote: remote)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            model.settings.backgroundColor.color
                .ignoresSafeArea()

            PrompterScrollView(
                text: model.script.text,
                settings: model.settings,
                engine: model.engine
            )
            .ignoresSafeArea(.container, edges: .vertical)

            if model.settings.showReadingGuide {
                ReadingGuideView(
                    position: model.settings.readingPosition,
                    color: model.settings.textColor.color
                )
                .ignoresSafeArea(.container, edges: .vertical)
            }

            if let feedback = model.feedback {
                FeedbackToast(text: feedback)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, isCompactHeight ? 68 : 96)
            }

            if model.controlsVisible {
                controls
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let countdown = model.countdown {
                CountdownOverlay(number: countdown, color: model.settings.textColor.color)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.handleScreenTap()
        }
        .onAppear { model.activate() }
        .onDisappear { model.deactivate() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.pauseForInterruption() }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
        .accessibilityLabel("Телесуфлёр")
    }

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, isCompactHeight ? 6 : 8)

            Spacer(minLength: 0)

            if isCompactHeight {
                compactLandscapePanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                portraitBottomPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ControlButton(symbol: "xmark", size: 18) {
                onClose()
            }
            .accessibilityLabel("Закрыть суфлёр")

            VStack(alignment: .leading, spacing: 3) {
                Text(model.script.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.remoteConnected ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(model.remoteConnected ? "Пульт" : "Без пульта")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Осталось ~\(model.formattedRemainingTime)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                model.toggleMirror()
                model.registerInteraction()
            } label: {
                Label("Зеркало", systemImage: "arrow.left.and.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(model.settings.mirrored ? .orange : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var portraitBottomPanel: some View {
        VStack(spacing: 14) {
            speedSliderRow
            fontSliderRow
            positionSlider

            HStack(spacing: 18) {
                transportButtons
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var compactLandscapePanel: some View {
        VStack(spacing: 10) {
            positionSlider

            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    speedSliderRow
                    fontSliderRow
                }

                HStack(spacing: 10) {
                    transportButtons
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var speedSliderRow: some View {
        HStack(spacing: 10) {
            Text("Скорость")
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            Slider(
                value: Binding(
                    get: { model.settings.speed },
                    set: { model.setSpeed($0) }
                ),
                in: PrompterSettings.speedRange,
                step: 5
            )
            Text("\(Int(model.settings.speed))")
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var fontSliderRow: some View {
        HStack(spacing: 10) {
            Text("Шрифт")
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            Slider(
                value: Binding(
                    get: { model.settings.fontSize },
                    set: { model.setFontSize($0) }
                ),
                in: PrompterSettings.fontRange,
                step: 1
            )
            Text("\(Int(model.settings.fontSize))")
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var positionSlider: some View {
        Slider(
            value: Binding(
                get: { scrubValue ?? model.progress },
                set: { newValue in
                    scrubValue = newValue
                    model.seek(toProgress: newValue)
                }
            ),
            in: 0...1
        ) { editing in
            if editing {
                model.beginScrubbing()
            } else {
                scrubValue = nil
            }
        }
        .accessibilityLabel("Позиция текста")
    }

    @ViewBuilder
    private var transportButtons: some View {
        ControlButton(symbol: "backward.end.fill") {
            model.restart()
            model.registerInteraction()
        }
        .accessibilityLabel("В начало")

        ControlButton(symbol: "gobackward") {
            model.engine.seekPage(forward: false)
            model.registerInteraction()
        }
        .accessibilityLabel("Назад на фрагмент")

        Button {
            model.togglePlayback()
            model.registerInteraction()
        } label: {
            Image(systemName: model.isPlaying || model.countdown != nil ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: isCompactHeight ? 52 : 64, weight: .regular))
                .foregroundStyle(.orange)
                .frame(width: isCompactHeight ? 58 : 72, height: isCompactHeight ? 58 : 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPlaying ? "Пауза" : "Старт")

        ControlButton(symbol: "goforward") {
            model.engine.seekPage(forward: true)
            model.registerInteraction()
        }
        .accessibilityLabel("Вперёд на фрагмент")

        ControlButton(
            symbol: "arrow.left.and.right",
            isActive: model.settings.mirrored
        ) {
            model.toggleMirror()
            model.registerInteraction()
        }
        .accessibilityLabel("Зеркало")
    }
}