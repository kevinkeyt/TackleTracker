import Foundation

/// Shelf order: the inventory list groups items in this order.
nonisolated enum Category: String, CaseIterable, Identifiable, Codable, Sendable {
    case softPlastic = "soft_plastic"
    case hardBait = "hard_bait"
    case terminal
    case line
    case rod
    case reel
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .softPlastic: "Soft plastics"
        case .hardBait: "Hard baits"
        case .terminal: "Terminal"
        case .line: "Line"
        case .rod: "Rods"
        case .reel: "Reels"
        case .other: "Other"
        }
    }

    /// Suggestions for the Type field.
    var types: [String] {
        switch self {
        case .softPlastic: ["Worm", "Stick bait", "Craw", "Creature", "Swimbait", "Fluke", "Tube", "Grub", "Trailer", "Ned", "Frog"]
        case .hardBait: ["Crankbait", "Jerkbait", "Topwater", "Lipless", "Spinnerbait", "Bladed jig", "Jig", "Swimbait", "Glide bait", "Buzzbait", "Spoon", "Frog"]
        case .terminal: ["Hooks", "Weights", "Jig heads", "Swivels", "Bobber stops", "Beads", "Split rings"]
        case .line: ["Fluorocarbon", "Monofilament", "Braid"]
        case .rod: ["Casting", "Spinning"]
        case .reel: ["Baitcasting", "Spinning"]
        case .other: []
        }
    }

    /// Extra fields worth tracking for gear that isn't sold in packs.
    var specFields: [String] {
        switch self {
        case .rod: ["Length", "Power", "Action", "Pieces", "Line rating", "Lure rating"]
        case .reel: ["Gear ratio", "Retrieve", "Size", "Line on it"]
        case .line: ["Test (lb)", "Yards"]
        default: []
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    init(lenient raw: String?) {
        self = Category(rawValue: raw ?? "") ?? .other
    }

    /// Best guess from a product title. The user can always change it.
    static func guess(from title: String?) -> Category {
        let t = (title ?? "").lowercased()
        func has(_ pattern: String) -> Bool { t.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\breel\b"#) { return .reel }
        if has(#"\brod\b|casting rod|spinning rod"#) { return .rod }
        if has(#"\bline\b|fluorocarbon|monofilament|\bbraid"#) { return .line }
        if has(#"\bhooks?\b|weights?\b|sinker|\bjig head|swivel|split ring|snap|bobber|bead|peg"#) { return .terminal }
        if has(#"crank|jerkbait|topwater|popper|walking|spinnerbait|chatter|bladed|buzzbait|swimbait|glide|lipless|spoon|frog|jig\b|underspin|wakebait|prop"#) {
            // Soft swimbaits and frogs come in packs too, but hard bodies are the common case.
            return has(#"soft|paddle ?tail|\d+\s*pk\b"#) ? .softPlastic : .hardBait
        }
        if has(#"worm|craw|creature|grub|tube|stick ?bait|senko|minnow|shad|fluke|trailer|beaver|\d+\s*pk\b|soft"#) { return .softPlastic }
        return .other
    }
}

nonisolated enum Units {
    static let all = ["pack", "each", "bag", "spool", "box"]

    static func label(_ unit: String, count: Int) -> String {
        count == 1 ? unit : unit.hasSuffix("x") ? unit + "es" : unit + "s"
    }
}
