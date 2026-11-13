import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

@main
struct TeleprompterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var scriptStore = ScriptStore()
    @StateObject private var remoteManager = RemoteInputManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
                .environmentObject(scriptStore)
                .environmentObject(remoteManager)
                .preferredColorScheme(settingsStore.settings.theme.colorScheme)
                .onAppear {
                    remoteManager.start()
                    OrientationController.apply(settingsStore.settings.orientationLock)
                }
                .onChange(of: settingsStore.settings.orientationLock) { newLock in
                    OrientationController.apply(newLock)
                }
                .alert(
                    "Ошибка сохранения",
                    isPresented: Binding(
                        get: { scriptStore.errorMessage != nil },
                        set: { if !$0 { scriptStore.errorMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(scriptStore.errorMessage ?? "")
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Сценарии", systemImage: "doc.text.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "slider.horizontal.3")
                }
        }
        .tint(.orange)
    }
}

@MainActor
enum OrientationController {
    static func apply(_ lock: ScreenOrientationLock) {
        AppDelegate.orientationLock = lock.interfaceOrientationMask

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: lock.interfaceOrientationMask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}