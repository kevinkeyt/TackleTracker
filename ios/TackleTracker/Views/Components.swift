import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: Thumbnail

/// The item's photo, its web image, or a plain system placeholder.
struct Thumb: View {
    var photo: Data?
    var imageURL: String?
    var size: CGFloat = 44

    init(item: Item, size: CGFloat = 44) {
        self.init(photo: item.photo, imageURL: item.imageURL, size: size)
    }

    init(photo: Data?, imageURL: String?, size: CGFloat = 44) {
        self.photo = photo
        self.imageURL = imageURL
        self.size = size
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let photo, let image = ThumbCache.image(for: photo) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemFill)
            Image(systemName: "photo")
                .font(.system(size: size * 0.38))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Decoding a JPEG on every redraw makes long lists stutter; keep the decoded images around.
enum ThumbCache {
    private static let cache = NSCache<NSData, UIImage>()

    static func image(for data: Data) -> UIImage? {
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 400, height: 400)) ?? UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: Rows

/// Photo, name, one-line summary and status, as used by every list of items.
struct ItemRow: View {
    let item: Item
    /// Shown on the trailing edge; defaults to the quantity on hand.
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            Thumb(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.headline).lineLimit(2)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                status
            }
            Spacer(minLength: 8)
            Text(trailing ?? "\(item.quantity)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(trailing ?? "\(item.quantity) on hand")
        }
    }

    @ViewBuilder private var status: some View {
        let parts = [item.location, item.isLow ? nil : (item.onList ? "On reorder list" : nil)].compactMap { $0 }
        if item.isLow || !parts.isEmpty {
            HStack(spacing: 6) {
                if item.isLow {
                    Label("Low", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}

/// Swipe and long-press actions shared by the inventory and scan lists.
struct QuantityActions: ViewModifier {
    let item: Item
    var onDelete: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { item.adjust(by: 1) } label: { Label("Add one", systemImage: "plus") }
                    .tint(.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                }
                Button { item.adjust(by: -1) } label: { Label("Take one out", systemImage: "minus") }
                    .tint(.orange)
                    .disabled(item.quantity == 0)
            }
            .contextMenu {
                Button { item.adjust(by: 1) } label: { Label("Add one", systemImage: "plus") }
                Button { item.adjust(by: -1) } label: { Label("Take one out", systemImage: "minus") }
                    .disabled(item.quantity == 0)
                Button {
                    item.onList.toggle()
                    item.updatedAt = .now
                } label: {
                    Label(item.onList ? "Remove from reorder list" : "Add to reorder list", systemImage: item.onList ? "cart.badge.minus" : "cart.badge.plus")
                }
                Link(destination: item.shopURL) { Label("Shop", systemImage: "safari") }
                if let onDelete {
                    Divider()
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                }
            }
    }
}

extension View {
    func quantityActions(_ item: Item, onDelete: (() -> Void)? = nil) -> some View {
        modifier(QuantityActions(item: item, onDelete: onDelete))
    }
}

// MARK: Formatting

enum Money {
    static func string(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.currency(code: "USD"))
    }

    static func whole(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

// MARK: Files

/// The backup file handed to the system "Save to Files" sheet.
nonisolated struct JSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The spreadsheet export, shared through the system share sheet.
nonisolated struct CSVFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
