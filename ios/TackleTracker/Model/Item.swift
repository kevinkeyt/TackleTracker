import Foundation
import SwiftData

/// One thing on the shelf: a pack of worms in one color, a rod, a spool of line.
///
/// Kept iCloud-ready: every property has a default or is optional and nothing is marked unique,
/// which is what CloudKit sync requires if it gets turned on later.
@Model
final class Item {
    var name: String = ""
    var brand: String?
    var categoryRaw: String = Category.other.rawValue
    var lureType: String?
    var color: String?
    var size: String?
    var quantity: Int = 0
    var unit: String = "pack"
    /// Reorder at or below this many. 0 = never flag.
    var minQuantity: Int = 0
    var location: String?
    /// Digits only, without leading zeros (see `UPC.normalize`).
    var upc: String?
    var sku: String?
    var price: Double?
    /// JPEG stored on the phone.
    @Attribute(.externalStorage) var photo: Data?
    /// A web image to show when there's no stored photo (the download failed when it was added).
    var imageURL: String?
    var productURL: String?
    var specs: [String: String] = [:]
    var notes: String?
    var onList: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String = "", category: Category = .softPlastic) {
        self.name = name
        self.categoryRaw = category.rawValue
    }

    var category: Category {
        get { Category(lenient: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var isLow: Bool { minQuantity > 0 && quantity <= minQuantity }
    var needsReorder: Bool { isLow || onList }

    /// How many to buy to get back above the reorder point, with a little headroom.
    var suggestedBuy: Int { max(1, minQuantity * 2 - quantity) }

    func adjust(by delta: Int) {
        quantity = max(0, quantity + delta)
        updatedAt = .now
    }

    /// Leaves out the brand when the name already starts with it ("Zoom Trick Worm").
    private var brandIfNotInName: String? {
        guard let brand, !brand.isEmpty, !name.lowercased().hasPrefix(brand.lowercased()) else { return nil }
        return brand
    }

    /// One-line summary under the name.
    var summary: String {
        [brandIfNotInName, lureType, color, size].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
    }

    /// "Zoom Trick Worm (Green Pumpkin)"
    var label: String {
        color.map { "\(name) (\($0))" } ?? name
    }

    /// Where the Shop button goes: the saved product page, else a Tackle Warehouse search for it.
    var shopURL: URL {
        if let productURL, let url = URL(string: productURL) { return url }
        let text = [brandIfNotInName, name, color].compactMap { $0?.nilIfBlank }.joined(separator: " ")
        return TackleWarehouse.searchURL(text)
    }

    var searchText: String {
        [name, brand, lureType, color, size, location, upc, sku].compactMap { $0 }.joined(separator: " ").lowercased()
    }

    /// The shelf order used everywhere: category, then brand, name, color.
    static func shelfOrder(_ a: Item, _ b: Item) -> Bool {
        if a.category != b.category { return a.category.order < b.category.order }
        for (x, y) in [(a.brand ?? "", b.brand ?? ""), (a.name, b.name), (a.color ?? "", b.color ?? "")] {
            let r = x.localizedStandardCompare(y)
            if r != .orderedSame { return r == .orderedAscending }
        }
        return false
    }
}

extension String {
    nonisolated var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension Optional where Wrapped == String {
    nonisolated var nilIfBlank: String? { self?.nilIfBlank }
}
