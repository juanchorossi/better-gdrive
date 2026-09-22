import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we start as menu-bar-only (guard against any state restoration
        // that may have bumped the policy to .regular before this fires).
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct BetterGDriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = StatusStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .task {
                    if store.needsSetup {
                        openWindow(id: "onboarding")
                    }
                }
        } label: {
            HStack(spacing: 0) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 16)
                let suffix = store.menuBarSuffix
                if !suffix.isEmpty {
                    Text("\u{2006}\(suffix)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
            .padding(.horizontal, 4)
        }
        .menuBarExtraStyle(.window)

        Window(L.General.appName, id: "main") {
            MainWindowView()
                .environmentObject(store)
                .onDisappear {
                    if NSApp.windows.filter({ !($0 is NSPanel) && $0.isVisible }).isEmpty {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(L.General.appName)") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: L.General.appName,
                        .version: "1.0.0",
                        .credits: NSAttributedString(string: "Sync your folders to Google Drive with rclone.")
                    ])
                }
            }
        }

        Window("Set up Better GDrive", id: "onboarding") {
            OnboardingView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Sync detail", id: "detail") {
            DetailView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
