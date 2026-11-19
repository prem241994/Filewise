import AppKit
import FilewiseCore
import QuickLookThumbnailing
import QuickLookUI
import SwiftUI

/// Quick Look thumbnails (the previews Finder shows), generated on this Mac
/// and kept in memory. Files without a preview keep their type icon.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    /// Files Quick Look could not preview, so they are not retried while scrolling.
    private var failed = Set<String>()

    private init() { cache.countLimit = 800 }

    private func key(_ item: FileItem, _ size: CGFloat) -> String {
        "\(item.id)|\(item.modified.timeIntervalSince1970)|\(item.size)|\(Int(size))"
    }

    func cached(_ item: FileItem, size: CGFloat) -> NSImage? {
        cache.object(forKey: key(item, size) as NSString)
    }

    func thumbnail(for item: FileItem, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = key(item, size)
        if let image = cache.object(forKey: key as NSString) { return image }
        // App bundles and empty files have nothing to preview.
        guard !failed.contains(key), item.kind != "app", item.size > 0 else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        let image = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: GeneratedImage(image: representation?.nsImage))
            }
        }.image
        if let image {
            cache.setObject(image, forKey: key as NSString)
        } else {
            failed.insert(key)
        }
        return image
    }
}

/// Carries a freshly generated image to the main actor. Older SDKs do not
/// mark NSImage as Sendable; it is never used again on the generating thread.
private struct GeneratedImage: @unchecked Sendable {
    let image: NSImage?
}

/// A file's preview: the photo itself, a frame of a video, or the first page
/// of a document, falling back to its type icon.
struct FileThumbnail: View {
    let item: FileItem
    let size: CGFloat
    /// Photos and videos fill the square; documents are shown whole.
    var fill = true
    var cornerRadius: CGFloat = 5
    /// When set, the play badge on a video is a button.
    var onPlay: (() -> Void)?
    var showsPlayBadge = true

    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?

    private var isVideo: Bool { item.libraryCategory == "Videos" }
    private var fills: Bool { fill && (item.isImage || isVideo) }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: fills ? cornerRadius : 2))
                    .overlay {
                        if fills {
                            RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.hairline)
                        }
                    }
            } else {
                Image(nsImage: IconCache.shared.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomLeading) {
            if isVideo && image != nil && showsPlayBadge {
                if let onPlay {
                    Button(action: onPlay) { playBadge }
                        .buttonStyle(.plain)
                        .help("Play")
                } else {
                    playBadge
                }
            }
        }
        .task(id: ThumbnailID(item: item, size: size)) {
            image = ThumbnailCache.shared.cached(item, size: size)
            if image == nil {
                image = await ThumbnailCache.shared.thumbnail(for: item, size: size, scale: scale)
            }
        }
        .accessibilityHidden(true)
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: max(7, size * 0.16), weight: .bold))
            .foregroundStyle(.white)
            .padding(max(2, size * 0.06))
            .background(.black.opacity(0.55), in: Circle())
            .padding(max(2, size * 0.06))
            .contentShape(Circle())
    }
}

private struct ThumbnailID: Equatable {
    let path: String
    let modified: Date
    let size: CGFloat

    init(item: FileItem, size: CGFloat) {
        path = item.id
        modified = item.modified
        self.size = size
    }
}

/// A gallery tile: a large preview with the file's name and size.
struct MediaTile: View {
    let item: FileItem
    let side: CGFloat
    let isSelected: Bool
    var onPlay: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            FileThumbnail(item: item, size: side, cornerRadius: Theme.Radius.m,
                          onPlay: item.libraryCategory == "Videos" ? onPlay : nil)
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.m + 3)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(item.displaySize)
                    if let reason = item.cleanupReasons.first {
                        Text("·")
                        Text(reason.label).foregroundStyle(Theme.color(for: reason))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 3)
        }
        .frame(width: side + 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.displaySize)\(item.cleanupReasons.map { ", " + $0.label }.joined())")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            if let onPlay, item.libraryCategory == "Videos" { Button("Play", action: onPlay) }
        }
    }
}

/// The inspector's preview. Videos play and documents can be read page by
/// page in a live Quick Look view; photos and other files show a thumbnail,
/// or their type icon when there is none.
struct InspectorPreview: View {
    let item: FileItem
    /// Starts a video as soon as it appears.
    var autoplay = false
    private let side: CGFloat = 220

    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?

    private var isMedia: Bool { item.isImage || isVideo }
    private var isVideo: Bool { item.libraryCategory == "Videos" }
    private var isDocument: Bool { item.libraryCategory == "Documents" }

    var body: some View {
        if (isVideo || isDocument) && item.size > 0 {
            QuickLookPreview(url: item.url, autoplay: autoplay)
                // Recreated per file and play request, so autoplay applies.
                .id("\(item.id)|\(autoplay)")
                .frame(height: isVideo ? 170 : 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.hairline))
                .accessibilityLabel(isVideo ? "Video player" : "Document preview")
        } else {
            thumbnail
        }
    }

    private var thumbnail: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: side, maxHeight: side * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: isMedia ? Theme.Radius.m : 0))
                    .overlay {
                        if isMedia { RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.hairline) }
                    }
                    .shadow(color: .black.opacity(isMedia ? 0.12 : 0.08), radius: 6, y: 2)
            } else {
                Image(nsImage: IconCache.shared.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            }
        }
        .task(id: ThumbnailID(item: item, size: side)) {
            image = ThumbnailCache.shared.cached(item, size: side)
            if image == nil {
                image = await ThumbnailCache.shared.thumbnail(for: item, size: side, scale: scale)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An embedded Quick Look view: plays videos with standard controls and
/// shows scrollable documents, entirely on this Mac.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    let autoplay: Bool

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = autoplay
        view.shouldCloseWithWindow = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
