import SwiftUI

/// The iPad's own UI. Controls only — it never renders the web page
/// itself, so the iPad and the external monitor never show the same
/// thing.
struct ControllerView: View {
    @EnvironmentObject var engine: BrowserEngine
    @EnvironmentObject var display: ExternalDisplayManager
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var lockDiagnostics = PointerLockDiagnostics.shared

    @State private var urlText: String = ""
    @FocusState private var urlFieldFocused: Bool
    @State private var showSettings = false
    @State private var showDiagnostics = false

    /// True when the hardware keyboard and mouse belong to the page on
    /// the external display rather than to this iPad UI.
    private var mouseCaptured: Bool {
        display.isConnected && settings.pointerLockEnabled
    }

    var body: some View {
        NavigationView {
            Form {
                Section("External Display") {
                    LabeledContent("Status", value: display.isConnected ? "Connected" : "Disconnected")
                    if display.isConnected {
                        LabeledContent("Resolution", value: "\(Int(display.pixelResolution.width)) × \(Int(display.pixelResolution.height))")
                        LabeledContent("Window Size", value: "\(Int(display.pointSize.width)) × \(Int(display.pointSize.height)) pt")
                    }
                    Text("Mouse and keyboard connected to the dock are relayed directly into the page on the external display.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Toggle("Capture Mouse", isOn: $settings.pointerLockEnabled)
                    Text("Stops the mouse from also moving the iPad's own pointer, so the cursor can reach every edge of the external display. Turn off if the mouse stops responding.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                // Directly under External Display on purpose: reading
                // these usually means toggling Capture Mouse at the same
                // time, and that toggle has to stay on screen while the
                // group is expanded — the list can't be scrolled while
                // the mouse is captured.
                Section {
                    DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                        LabeledContent("UIKit reads", value: "\(lockDiagnostics.reads)")
                        LabeledContent("Last answer", value: lockDiagnostics.lastAnswer ? "locked" : "unlocked")
                        LabeledContent("Re-arms", value: "\(lockDiagnostics.rearms)")
                        LabeledContent("Reads since re-arm", value: "\(lockDiagnostics.readsSinceLastRearm)")
                        LabeledContent("Last trigger", value: lockDiagnostics.lastRearmReason)
                        LabeledContent("Last key sent", value: lockDiagnostics.lastKey)

                        Text("Raw keys (newest first)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(lockDiagnostics.rawKeys, id: \.self) { entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                        }

                        Button("Re-arm: ask UIKit") {
                            NotificationCenter.default.post(name: AppSettings.pointerLockPreferenceChanged, object: nil)
                        }
                        Button("Re-arm: rebuild screen") {
                            NotificationCenter.default.post(name: PointerLockDiagnostics.requestRootSwap, object: nil)
                        }
                        Button("Re-arm: nudge geometry") {
                            NotificationCenter.default.post(name: PointerLockDiagnostics.requestGeometryNudge, object: nil)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                Section("Address") {
                    if mouseCaptured {
                        Text("Use the address bar on the external display. This field is disabled so the keyboard can't type into both at once.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    TextField("https://example.com", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($urlFieldFocused)
                        .onSubmit { openTypedURL() }

                    Button("Go") { openTypedURL() }
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                // Anything the hardware keyboard could focus or activate is
                // disabled while the mouse is captured: the keyboard belongs
                // to the external display then, and Tab/Enter would otherwise
                // also walk and press these controls.
                .disabled(mouseCaptured)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                Section("Browser") {
                    if let error = engine.state.errorMessage {
                        Text(error).foregroundColor(.red).font(.footnote)
                    }

                    HStack(spacing: 20) {
                        Button { engine.goBack() } label: { Image(systemName: "chevron.left") }
                            .disabled(!engine.state.canGoBack)
                        Button { engine.goForward() } label: { Image(systemName: "chevron.right") }
                            .disabled(!engine.state.canGoForward)
                        Button { engine.state.isLoading ? engine.stop() : engine.reload() } label: {
                            Image(systemName: engine.state.isLoading ? "xmark" : "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)

                    Button(engine.state.isFullScreen ? "Exit Full Screen" : "Full Screen") {
                        engine.toggleFullScreen()
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                Section {
                    Button("Settings") { showSettings = true }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Tightened up: the stock form spacing wastes a lot of
            // vertical room, and this screen has to stay readable without
            // scrolling while the mouse is captured. There's a limit to
            // how far this goes before it stops behaving like a normal
            // iPad list, so it's reduced rather than eliminated.
            .environment(\.defaultMinListRowHeight, 26)
            .navigationTitle("External Browser")
            .navigationBarTitleDisplayMode(.inline)
            // The mouse wheel reaches this list as well as the page on the
            // external display, so it would scroll in the background while
            // browsing. Lock it while the mouse is captured — the "Capture
            // Mouse" toggle sits in the first section, so it stays
            // reachable to undo this without scrolling.
            .scrollDisabled(mouseCaptured)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            // Key commands reach the responder chain independently of raw
            // key presses, so they have to be withdrawn rather than
            // swallowed. Bare Escape especially: it's constant in a
            // terminal session and would otherwise also exit full screen.
            .background(mouseCaptured ? nil : keyboardShortcuts)
            .onAppear {
                urlText = engine.state.url?.absoluteString ?? ""
                engine.ensureDocumentLoaded()
            }
            .onChange(of: engine.state.url) { newValue in
                urlText = newValue?.absoluteString ?? urlText
            }
        }
        .navigationViewStyle(.stack)
    }

    private func openTypedURL() {
        urlFieldFocused = false
        engine.load(urlString: urlText)
    }

    /// Hidden buttons that give the external keyboard shortcuts from
    /// section 15 of the spec, without interfering with system shortcuts.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { urlFieldFocused = true }
                .keyboardShortcut("l", modifiers: .command)
            Button("") { engine.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { engine.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("") { engine.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Button("") { if engine.state.isFullScreen { engine.setFullScreen(false) } }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
