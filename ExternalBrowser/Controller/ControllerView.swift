import SwiftUI

/// The iPad's own UI. Controls only — it never renders the web page
/// itself, so the iPad and the external monitor never show the same
/// thing.
struct ControllerView: View {
    @EnvironmentObject var engine: BrowserEngine
    @EnvironmentObject var display: ExternalDisplayManager
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var relay = InputRelay.shared

    @State private var urlText: String = ""
    @FocusState private var urlFieldFocused: Bool
    @State private var showSettings = false

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

                    // Kept in this first section so it stays reachable by
                    // touch: the list can't be scrolled while the mouse is
                    // captured, which put the copy further down out of
                    // reach.
                    Button(engine.state.isFullScreen ? "Exit Full Screen" : "Full Screen") {
                        engine.toggleFullScreen()
                    }

                    if mouseCaptured {
                        Text("From the external keyboard: ⌘⇧F toggles full screen, ⌘⇧M toggles mouse capture.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Input Diagnostics") {
                    LabeledContent("Relay attached", value: relay.isAttached ? "Yes" : "No")
                    LabeledContent("Mouse", value: relay.mouseConnected ? "Connected" : "Not connected")
                    LabeledContent("Keyboard", value: relay.keyboardConnected ? "Connected" : "Not connected")
                    LabeledContent("Move events", value: "\(relay.moveEvents)")
                    LabeledContent("Scroll events", value: "\(relay.scrollEvents)")
                    LabeledContent("Key events", value: "\(relay.keyEvents)")
                    Text(relay.diagnostic)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

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

                Section("Browser") {
                    LabeledContent("Loading", value: engine.state.isLoading ? "Yes" : "No")
                    LabeledContent("Back", value: engine.state.canGoBack ? "Enabled" : "Disabled")
                    LabeledContent("Forward", value: engine.state.canGoForward ? "Enabled" : "Disabled")
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
                }

                Section {
                    Button("Settings") { showSettings = true }
                }
            }
            .navigationTitle("External Browser")
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
                if engine.state.url == nil {
                    engine.load(urlString: AppSettings.shared.homepage)
                }
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
