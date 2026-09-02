import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: BrowserEngine
    @EnvironmentObject var display: ExternalDisplayManager
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var homepageText: String = ""
    @State private var isClearing = false
    @State private var clearedMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Browser") {
                    TextField("Homepage URL", text: $homepageText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { settings.homepage = homepageText }

                    Button(isClearing ? "Clearing…" : "Clear Website Data") {
                        isClearing = true
                        engine.clearWebsiteData {
                            isClearing = false
                            clearedMessage = "Website data cleared."
                        }
                    }
                    .disabled(isClearing)

                    if let message = clearedMessage {
                        Text(message).font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section("Keyboard") {
                    Toggle("PC Keyboard", isOn: $settings.pcKeyboardMode)
                    Text("Swaps Command and Alt. iPadOS makes the key next to the spacebar act as Command, which on a PC keyboard is Alt — so without this, pressing Alt sends Command and a remote session never receives Alt. Turn off when using an Apple keyboard.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Downloads") {
                    if downloads.items.isEmpty {
                        Text("Saved files appear here, and in the Files app under On My iPad → External Browser → Downloads.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(downloads.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename)
                                if let failure = item.failure {
                                    Text(failure).font(.footnote).foregroundColor(.red)
                                } else {
                                    Text(item.finished ? "Saved" : "Downloading…")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("External Display") {
                    Toggle("Start in Full Screen", isOn: $settings.startInFullScreen)
                    Toggle("Automatically Activate Browser", isOn: $settings.autoActivateBrowser)

                    LabeledContent("Status", value: display.isConnected ? "Connected" : "Disconnected")
                    if display.isConnected {
                        LabeledContent("Resolution", value: "\(Int(display.pixelResolution.width)) × \(Int(display.pixelResolution.height))")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersionString)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        settings.homepage = homepageText
                        dismiss()
                    }
                }
            }
            .onAppear { homepageText = settings.homepage }
        }
        .navigationViewStyle(.stack)
    }
}

extension Bundle {
    var appVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
