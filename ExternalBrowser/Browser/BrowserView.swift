import SwiftUI
import WebKit

/// The view shown on the EXTERNAL monitor. Never shown on the iPad itself.
struct BrowserView: View {
    @EnvironmentObject var engine: BrowserEngine

    var body: some View {
        VStack(spacing: 0) {
            if !engine.state.isFullScreen {
                toolbar
            }
            WebViewRepresentable(webView: engine.webView)
        }
        .ignoresSafeArea()
        .background(Color.black)
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(action: engine.goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!engine.state.canGoBack)

                Button(action: engine.goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!engine.state.canGoForward)

                Button(action: engine.reload) {
                    Image(systemName: engine.state.isLoading ? "xmark" : "arrow.clockwise")
                }
                .onTapGesture {
                    engine.state.isLoading ? engine.stop() : engine.reload()
                }

                Text(engine.state.url?.absoluteString ?? "")
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if engine.state.isLoading {
                ProgressView(value: engine.state.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }
        }
        .background(.thinMaterial)
    }
}

/// Wraps the single persistent WKWebView instance. makeUIView always
/// returns the same shared view (never a new one), so re-parenting this
/// into a freshly created SwiftUI hierarchy (e.g. after a display
/// reconnect) does not reload the page or lose session state.
struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
