import SwiftUI

@main
struct OpenClawRemoteApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
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
    }
}
