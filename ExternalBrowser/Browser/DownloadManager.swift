import WebKit
import Combine

/// Saves downloads straight into the app's Documents folder rather than
/// asking where to put them.
///
/// A save dialog is native UI, and the external display accepts no input
/// at all, so any picker would have to be answered by touching the iPad —
/// defeating the point of working entirely on the monitor. Files land in
/// a Downloads folder that is exposed through the Files app (see
/// UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace in
/// project.yml), so they can be moved or opened from there afterwards.
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    struct Item: Identifiable {
        let id = UUID()
        let filename: String
        let date: Date
        var finished: Bool
        var failure: String?
    }

    @Published private(set) var items: [Item] = []

    private var itemsByDownload: [ObjectIdentifier: UUID] = [:]

    private override init() { super.init() }

    var downloadsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func track(_ download: WKDownload) {
        download.delegate = self
    }

    /// Never overwrites: "report.pdf" becomes "report-2.pdf" and so on.
    private func uniqueURL(for filename: String) -> URL {
        let directory = downloadsDirectory
        var candidate = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var counter = 2
        repeat {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let destination = uniqueURL(for: name)

        let item = Item(filename: destination.lastPathComponent, date: Date(), finished: false, failure: nil)
        items.insert(item, at: 0)
        itemsByDownload[ObjectIdentifier(download)] = item.id

        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        update(download) { $0.finished = true }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        update(download) {
            $0.finished = true
            $0.failure = error.localizedDescription
        }
    }

    private func update(_ download: WKDownload, _ change: (inout Item) -> Void) {
        guard let id = itemsByDownload[ObjectIdentifier(download)],
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        itemsByDownload.removeValue(forKey: ObjectIdentifier(download))
    }
}
