import SwiftUI

@main
struct OpenClawRemoteApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.light)
                .id(model.language)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.appDidBecomeActive() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.isConnected {
                ChatView()
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $model.showScanner) {
            ScannerView { code in
                model.showScanner = false
                model.connect(pairingCode: code)
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $model.showSessions) {
            SessionListView()
        }
        .onOpenURL { url in
            model.connect(pairingCode: url.absoluteString)
        }
        .task {
            model.autoConnect()   // 已配對過就直接連(device token 在 Keychain)
        }
    }
}
