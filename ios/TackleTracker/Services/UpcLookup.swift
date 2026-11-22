import Foundation

/// What a barcode lookup knows about a package you don't own yet.
nonisolated struct UpcSuggestion: Sendable, Hashable {
    var name: String?
    var brand: String?
    var color: String?
    var size: String?
    var image: URL?
    var category: Category
}

/// The free UPCitemdb lookup only answers its own website, so it goes through a tiny relay
/// (worker/upc-relay.js on Cloudflare's free tier). Without one, unknown barcodes just aren't prefilled.
nonisolated enum UpcLookup {
    static let defaultRelay = "https://tackletracker-upc-relay.bassbot.workers.dev"
    static let relayKey = "upcRelayUrl"

    static var relay: String {
        UserDefaults.standard.string(forKey: relayKey) ?? defaultRelay
    }

    static func lookup(_ code: String) async -> UpcSuggestion? {
        guard let upc = UPC.normalize(code), !relay.isEmpty, var c = URLComponents(string: relay) else { return nil }
        let padded = String(repeating: "0", count: max(0, 12 - upc.count)) + upc
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "upc", value: padded)]
        guard let url = c.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return parse(data)
        } catch {
            return nil
        }
    }

    static func parse(_ data: Data) -> UpcSuggestion? {
        struct Response: Decodable {
            struct Entry: Decodable {
                var title: String?
                var brand: String?
                var color: String?
                var size: String?
                var images: [String]?
            }
            var items: [Entry]?
        }
        guard let item = (try? JSONDecoder().decode(Response.self, from: data))?.items?.first else { return nil }
        return UpcSuggestion(
            name: item.title.nilIfBlank,
            brand: item.brand.nilIfBlank,
            color: item.color.nilIfBlank,
            size: item.size.nilIfBlank,
            image: item.images?.first { $0.hasPrefix("https:") }.flatMap(URL.init(string:)),
            category: .guess(from: item.title)
        )
    }
}
