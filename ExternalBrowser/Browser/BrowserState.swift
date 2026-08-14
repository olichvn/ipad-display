import Foundation

struct BrowserState {
    var url: URL?
    var title: String?
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var progress: Double = 0
    var isFullScreen: Bool = false
    var errorMessage: String?
}
