import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: StatusStore
    @Environment(\.openWindow)    private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var clientId:     String = KeychainStore.load("client_id")     ?? ""
    @State private var clientSecret: String = KeychainStore.load("client_secret") ?? ""
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?

    enum Phase { case idle, configuring, waitingForBrowser, done }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 460)
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.blue)

            Text("Connect to Google Drive")
                .font(.title2.bold())

            Text("Enter your GCP OAuth credentials.\nEach user authenticates their own Google account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(label: "Client ID",
                  placeholder: "123456789-abc…apps.googleusercontent.com",
                  text: $clientId)

            field(label: "Client Secret",
                  placeholder: "GOCSPX-…",
                  text: $clientSecret,
                  secure: true)

            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                Link("How to create your GCP credentials →",
                     destination: URL(string: "https://github.com/juanchorossi/better-gdrive#gcp-setup")!)
            }
            .font(.caption)
        }
        .padding(24)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: connect) {
                buttonLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canConnect)

            if phase == .waitingForBrowser {
                Text("Complete the sign-in in the browser window that just opened, then come back here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        switch phase {
        case .idle:
            Label("Connect with Google Drive", systemImage: "arrow.right.circle.fill")
        case .configuring:
            Label("Configuring…", systemImage: "gearshape")
        case .waitingForBrowser:
            Label("Waiting for browser sign-in…", systemImage: "globe")
        case .done:
            Label("Connected!", systemImage: "checkmark.circle.fill")
        }
    }

    private var canConnect: Bool {
        !clientId.trimmingCharacters(in: .whitespaces).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty &&
        phase == .idle
    }

    // MARK: Helpers

    @ViewBuilder
    private func field(label: String, placeholder: String,
                       text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.bold())
            if secure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: Action

    private func connect() {
        errorMessage = nil
        let id     = clientId.trimmingCharacters(in: .whitespaces)
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)

        Task {
            phase = .configuring

            do {
                KeychainStore.save(id,     for: "client_id")
                KeychainStore.save(secret, for: "client_secret")

                try RcloneRC.createGDriveConfig(clientId: id, clientSecret: secret)

                phase = .waitingForBrowser
                try await RcloneRC.reconnectGDrive()
                await RcloneRC.waitForReconnectComplete()

                phase = .done
                await store.refreshAfterSetup()

                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    openWindow(id: "main")
                    dismissWindow(id: "onboarding")
                }
            } catch {
                phase = .idle
                errorMessage = "Connection failed. Check your credentials and try again."
            }
        }
    }
}
