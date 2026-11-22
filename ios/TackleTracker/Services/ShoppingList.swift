import Foundation

/// Plain-text shopping list for taking to the tackle store. Plain lines paste cleanly into Notes,
/// where they can be turned into a checklist.
nonisolated enum ShoppingList {
    struct Entry: Sendable {
        var name: String
        /// Brand (when not already in the name), color, size.
        var details: [String]
        var quantity: Int
        var unit: String
        var onHand: Int
        var price: Double?
        var link: URL?
        var category: Category
    }

    struct Options: Sendable {
        var showOnHand = true
        var showPrices = false
        var showLinks = false
    }

    static func text(_ entries: [Entry], options: Options, date: Date = .now) -> String {
        var lines = ["Tackle Shopping List", date.formatted(date: .complete, time: .omitted)]
        for category in Category.allCases {
            let group = entries.filter { $0.category == category }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append(category.label)
            for e in group {
                lines.append(line(for: e, options: options))
                if options.showLinks, let link = e.link { lines.append(link.absoluteString) }
            }
        }
        if options.showPrices {
            let total = entries.reduce(0.0) { $0 + ($1.price ?? 0) * Double($1.quantity) }
            if total > 0 {
                lines.append("")
                lines.append("Estimated total: \(total.formatted(.currency(code: "USD")))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "3 packs Zoom Trick Worm (Watermelon Red, 6.5"), have 1, $4.79 each"
    static func line(for e: Entry, options: Options) -> String {
        let count = e.unit == "each" ? "\(e.quantity) ×" : "\(e.quantity) \(Units.label(e.unit, count: e.quantity))"
        var line = "\(count) \(e.name)"
        if !e.details.isEmpty { line += " (\(e.details.joined(separator: ", ")))" }
        var extras: [String] = []
        if options.showOnHand { extras.append("have \(e.onHand)") }
        if options.showPrices, let price = e.price { extras.append("\(price.formatted(.currency(code: "USD"))) each") }
        if !extras.isEmpty { line += ", " + extras.joined(separator: ", ") }
        return line
    }
}
