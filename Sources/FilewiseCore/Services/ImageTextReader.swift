import Foundation
import Vision

/// Reads the text in an image with the Vision framework's on-device text
/// recognition. Nothing leaves the Mac. Safe to call from any thread; each
/// call is synchronous and can take a fraction of a second.
public enum ImageTextReader {
    /// Which images have their text read: screenshots, where the words are
    /// what people remember.
    public static func shouldRead(_ item: FileItem) -> Bool {
        item.isScreenshot
    }

    /// The recognized text, one line per detected line of text, or nil when
    /// the image can't be read. An image without text gives "".
    public static func read(_ url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}

/// Text read from one image, with the size and date it was read at so a
/// later refresh can tell whether the image changed.
public struct ImageTextEntry: Sendable, Equatable {
    public let path: String
    public let size: Int64
    public let modified: Date
    public let text: String

    public init(path: String, size: Int64, modified: Date, text: String) {
        self.path = path
        self.size = size
        self.modified = modified
        self.text = text
    }
}
