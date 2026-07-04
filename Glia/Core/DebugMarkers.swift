import Foundation

/// Unbuffered breadcrumbs for headless-pipeline diagnosis.
/// Active only when GLIA_MARKERS names a file; zero cost otherwise.
enum Markers {
    private static let path =
        ProcessInfo.processInfo.environment["GLIA_MARKERS"]

    static func drop(_ label: String) {
        guard let path else { return }
        let line = "\(Date().timeIntervalSince1970) \(label)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            try? fh.close()
        } else {
            try? line.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        }
    }
}
