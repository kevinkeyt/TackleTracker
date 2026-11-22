import Foundation
import SwiftData

/// Backups use the same JSON format as the old web app, so a backup from either restores into the other:
/// `{ app: "TackleTracker", version: 1, exported_at, items: [...], images: { id: "data:image/jpeg;base64,…" } }`.
/// An item's `image_url` is either "img:<id>" (a photo in `images`) or a web address.
enum Backup {
    static let lastKey = "lastBackupAt"
    static let remindDays = 14

    static var lastBackupAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: lastKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastKey) }
    }

    static var daysSinceBackup: Int? {
        lastBackupAt.map { Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0 }
    }

    static var stamp: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    // MARK: Export

    static func exportJSON(_ items: [Item]) throws -> Data {
        var images: [String: String] = [:]
        let records: [ItemRecord] = items.sorted(by: Item.shelfOrder).map { item in
            var imageRef = item.imageURL
            if let photo = item.photo {
                let id = UUID().uuidString.lowercased()
                images[id] = "data:image/jpeg;base64," + photo.base64EncodedString()
                imageRef = "img:\(id)"
            }
            return ItemRecord(item, imageRef: imageRef)
        }
        let file = BackupFile(app: "TackleTracker", version: 1, exported_at: isoString(.now), items: records, images: images)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    static var backupFilename: String { "tackle-backup-\(stamp).json" }
    static var csvFilename: String { "tackle-\(stamp).csv" }

    static func exportCSV(_ items: [Item]) -> String {
        let cols = ["name", "brand", "category", "type", "color", "size", "quantity", "unit", "min_quantity",
                    "location", "upc", "sku", "price", "product_url", "notes"]
        func esc(_ v: String?) -> String {
            guard let v else { return "" }
            return v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\"" : v
        }
        let rows = items.sorted(by: Item.shelfOrder).map { it in
            [it.name, it.brand, it.categoryRaw, it.lureType, it.color, it.size, String(it.quantity), it.unit, String(it.minQuantity),
             it.location, it.upc, it.sku, it.price.map { String($0) }, it.productURL, it.notes].map(esc).joined(separator: ",")
        }
        return ([cols.joined(separator: ",")] + rows).joined(separator: "\n")
    }

    // MARK: Import

    enum ImportError: LocalizedError {
        case notABackup
        var errorDescription: String? { "That file isn't a TackleTracker backup" }
    }

    /// Reads and checks a backup without touching the store, so the caller can ask "replace or add?" first.
    static func read(_ data: Data) throws -> BackupFile {
        guard let file = try? JSONDecoder().decode(BackupFile.self, from: data), file.app == "TackleTracker" else {
            throw ImportError.notABackup
        }
        return file
    }

    /// Adds the backup's items, or replaces everything when `replace` is true. Returns how many were restored.
    @discardableResult
    static func restore(_ file: BackupFile, replace: Bool, into context: ModelContext) throws -> Int {
        if replace { try context.delete(model: Item.self) }
        var count = 0
        for r in file.items {
            guard let name = r.name.nilIfBlank else { continue }
            let item = Item(name: name, category: Category(lenient: r.category))
            item.brand = r.brand.nilIfBlank
            item.lureType = r.type.nilIfBlank
            item.color = r.color.nilIfBlank
            item.size = r.size.nilIfBlank
            item.quantity = max(0, r.quantity ?? 0)
            item.unit = r.unit.nilIfBlank ?? "pack"
            item.minQuantity = max(0, r.min_quantity ?? 0)
            item.location = r.location.nilIfBlank
            item.upc = UPC.normalize(r.upc)
            item.sku = r.sku.nilIfBlank
            item.price = r.price.flatMap { $0 > 0 ? $0 : nil }
            item.productURL = r.product_url.nilIfBlank
            item.specs = r.specs ?? [:]
            item.notes = r.notes.nilIfBlank
            item.onList = r.on_list ?? false
            item.createdAt = r.created_at.flatMap(parseDate) ?? .now
            item.updatedAt = r.updated_at.flatMap(parseDate) ?? .now
            if let ref = r.image_url {
                if ref.hasPrefix("img:") {
                    item.photo = file.images?[String(ref.dropFirst(4))].flatMap(decodeDataURL)
                } else if ref.hasPrefix("https:") || ref.hasPrefix("http:") {
                    item.imageURL = ref
                }
            }
            context.insert(item)
            count += 1
        }
        try context.save()
        return count
    }

    static func decodeDataURL(_ s: String) -> Data? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(s[s.index(after: comma)...]))
    }

    // MARK: Dates (JavaScript writes ISO 8601 with milliseconds)

    static func isoString(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    static func parseDate(_ s: String) -> Date? {
        (try? Date(s, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(s, strategy: .iso8601))
    }
}

nonisolated struct BackupFile: Codable, Sendable {
    var app: String
    var version: Int?
    var exported_at: String?
    var items: [ItemRecord]
    var images: [String: String]?
}

/// One item as the web app wrote it. Every field is optional and decoded leniently so an odd value never sinks a restore.
nonisolated struct ItemRecord: Codable, Sendable {
    var name: String?
    var brand: String?
    var category: String?
    var type: String?
    var color: String?
    var size: String?
    var quantity: Int?
    var unit: String?
    var min_quantity: Int?
    var location: String?
    var upc: String?
    var sku: String?
    var price: Double?
    var image_url: String?
    var product_url: String?
    var specs: [String: String]?
    var notes: String?
    var on_list: Bool?
    var created_at: String?
    var updated_at: String?

    @MainActor init(_ it: Item, imageRef: String?) {
        name = it.name; brand = it.brand; category = it.categoryRaw; type = it.lureType; color = it.color; size = it.size
        quantity = it.quantity; unit = it.unit; min_quantity = it.minQuantity; location = it.location; upc = it.upc
        sku = it.sku; price = it.price; image_url = imageRef; product_url = it.productURL; specs = it.specs
        notes = it.notes; on_list = it.onList
        created_at = Backup.isoString(it.createdAt); updated_at = Backup.isoString(it.updatedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String? {
            if let s = try? c.decodeIfPresent(String.self, forKey: k) { return s }
            if let n = try? c.decodeIfPresent(Double.self, forKey: k) { return n.rounded() == n ? String(Int(n)) : String(n) }
            return nil
        }
        func num(_ k: CodingKeys) -> Double? {
            if let n = try? c.decodeIfPresent(Double.self, forKey: k) { return n }
            return (try? c.decodeIfPresent(String.self, forKey: k)).flatMap { $0.flatMap(Double.init) }
        }
        name = str(.name); brand = str(.brand); category = str(.category); type = str(.type); color = str(.color)
        size = str(.size); unit = str(.unit); location = str(.location); upc = str(.upc); sku = str(.sku)
        image_url = str(.image_url); product_url = str(.product_url); notes = str(.notes)
        created_at = str(.created_at); updated_at = str(.updated_at)
        quantity = num(.quantity).map { Int($0) }
        min_quantity = num(.min_quantity).map { Int($0) }
        price = num(.price)
        on_list = (try? c.decodeIfPresent(Bool.self, forKey: .on_list)) ?? nil
        specs = ((try? c.decodeIfPresent([String: String?].self, forKey: .specs)) ?? nil)?.compactMapValues { $0 }
    }
}
