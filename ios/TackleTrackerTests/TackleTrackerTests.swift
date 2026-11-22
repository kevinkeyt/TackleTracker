import Foundation
import SwiftData
import Testing
@testable import TackleTracker

struct UPCTests {
    @Test func normalizeStripsLeadingZerosAndNonDigits() {
        #expect(UPC.normalize("0 12345-67890 5") == "12345678905")
        #expect(UPC.normalize("0012345678905") == "12345678905")
        #expect(UPC.normalize("000") == nil)
        #expect(UPC.normalize(nil) == nil)
    }

    @Test func expandsUPCE() {
        #expect(UPC.expandUPCE("01234505") == "012000003455")
        #expect(UPC.expandUPCE("04252614") == "042100005264")
        #expect(UPC.expandUPCE("123456789012") == "123456789012")
    }

    @Test func typedCodes() {
        #expect(UPC.fromTyped("12345") == nil)
        #expect(UPC.fromTyped("04252614") == "042100005264")
        #expect(UPC.fromTyped("0 49694 01234 5") == "049694012345")
    }
}

struct CategoryTests {
    @Test func guessesFromTitles() {
        #expect(Category.guess(from: "Shimano Curado DC Casting Reel") == .reel)
        #expect(Category.guess(from: "Dobyns Fury Casting Rod") == .rod)
        #expect(Category.guess(from: "Seaguar InvizX Fluorocarbon Line") == .line)
        #expect(Category.guess(from: "Gamakatsu EWG Worm Hooks") == .terminal)
        #expect(Category.guess(from: "Strike King KVD 1.5 Squarebill Crankbait") == .hardBait)
        #expect(Category.guess(from: "Keitech Swing Impact FAT Swimbait 8pk") == .softPlastic)
        #expect(Category.guess(from: "Zoom Trick Worm") == .softPlastic)
        #expect(Category.guess(from: "Sunglasses") == .other)
    }
}

struct ProductPageTests {
    @Test func acceptsLinksFromAnyStore() throws {
        #expect(ProductPage.link(from: " https://www.basspro.com/shop/en/zoom-trick-worm#reviews ")?.absoluteString
                == "https://www.basspro.com/shop/en/zoom-trick-worm")
        #expect(ProductPage.link(from: "http://example-baits.com/products/craw")?.absoluteString == "https://example-baits.com/products/craw")
        #expect(ProductPage.link(from: "example-baits.com/products/craw")?.absoluteString == "https://example-baits.com/products/craw")
        #expect(ProductPage.link(from: "Zoom Trick Worm") == nil)
        #expect(ProductPage.link(from: "ftp://example.com/x") == nil)
        #expect(ProductPage.link(from: "") == nil)
    }

    /// Shopify-style JSON-LD: one Product with an offer per variant.
    @Test func readsJSONLDOffers() async throws {
        let html = """
        <html><head><title>Rage Craw | Example Baits</title>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Product","name":"Strike King Rage Craw",
         "brand":{"@type":"Brand","name":"Strike King"},"image":["https://cdn.example.com/craw.jpg"],
         "offers":[
          {"@type":"Offer","name":"Green Pumpkin","sku":"RC-GP","gtin12":"051525000016","price":"4.99","availability":"https://schema.org/InStock"},
          {"@type":"Offer","name":"Black Blue Flake","sku":"RC-BB","price":4.99,"availability":"https://schema.org/OutOfStock"}]}
        </script></head><body></body></html>
        """
        let p = try await ProductPage.parse(html: html, url: URL(string: "https://example-baits.com/products/rage-craw")!)
        #expect(p.name == "Strike King Rage Craw")
        #expect(p.brand == "Strike King")
        #expect(p.image?.absoluteString == "https://cdn.example.com/craw.jpg")
        #expect(p.category == .softPlastic)
        #expect(p.variants.map(\.title) == ["Green Pumpkin", "Black Blue Flake"])
        #expect(p.variants[0].upc == "51525000016")
        #expect(p.variants[0].price == 4.99)
        #expect(p.variants[0].inStock == "In stock")
        #expect(p.variants[1].inStock == "Out of stock")
    }

    /// JSON-LD inside an @graph, as a ProductGroup with variant Products.
    @Test func readsJSONLDProductGroup() async throws {
        let html = """
        <script type="application/ld+json">
        {"@graph":[{"@type":"WebPage","name":"ignored"},
          {"@type":"ProductGroup","name":"Gamakatsu EWG Worm Hook","brand":"Gamakatsu",
           "hasVariant":[
            {"@type":"Product","size":"3/0","sku":"G-30","offers":{"@type":"Offer","price":"5.99"}},
            {"@type":"Product","size":"4/0","sku":"G-40","gtin13":"0012345678905","offers":{"@type":"Offer","price":"6.49"}}]}]}
        </script>
        """
        let p = try await ProductPage.parse(html: html, url: URL(string: "https://shop.example.com/hooks")!)
        #expect(p.name == "Gamakatsu EWG Worm Hook")
        #expect(p.category == .terminal)
        #expect(p.variants.count == 2)
        #expect(p.variants[1].size == "4/0")
        #expect(p.variants[1].price == 6.49)
        #expect(p.variants[1].upc == "12345678905")
    }

    /// A single product: one option, so the form can fill in without asking.
    @Test func readsSingleProduct() async throws {
        let html = """
        <script type="application/ld+json">
        [{"@type":"Product","name":"Shimano Curado DC Casting Reel","sku":"CU-DC","gtin":"022255000012",
          "offers":{"@type":"AggregateOffer","lowPrice":"229.99","highPrice":"249.99"}}]
        </script>
        """
        let p = try await ProductPage.parse(html: html, url: URL(string: "https://store.example.com/reel")!)
        #expect(p.category == .reel)
        #expect(p.variants.count == 1)
        #expect(p.variants[0].price == 229.99)
        #expect(p.variants[0].sku == "CU-DC")
    }

    /// Microdata with one offer row per color, with relative swatch images.
    @Test func readsMicrodataOfferRows() async throws {
        let html = """
        <html><head><title>Zoom Trick Worm 20pk - Some Store</title>
        <meta itemprop="brand" content="Zoom"></head><body>
        <img itemprop="image" src="/image.php?path=zoom.jpg&nw=200" srcset="/image.php?path=zoom.jpg&nw=300 300w, /image.php?path=zoom.jpg&nw=900 900w">
        <table class="js-ordering-table" data-owner-name="Zoom Trick Worm 20pk">
          <tr itemprop="offers" data-code="ZTW-GP">
            <td class="js-ordering-name">Green Pumpkin</td>
            <td><meta itemprop="price" content="4.79"><meta itemprop="gtin12" content="074660000012"></td>
            <td class="js-ordering-style" data-stylethumb="/image.php?path=gp.jpg&nw=60">
              <span class="js-ordering-style-name">Color</span><span class="js-ordering-style-item-name">Green Pumpkin</span></td>
            <td class="js-ordering-style"><span class="js-ordering-style-name">Size</span><span class="js-ordering-style-item-name">6.5"</span></td>
            <td class="js-ordering-available">In Stock</td>
          </tr>
          <tr itemprop="offers" data-code="ZTW-WM">
            <td class="js-ordering-name">Watermelon Red</td><td><meta itemprop="price" content="4.79"></td>
          </tr>
        </table></body></html>
        """
        let p = try await ProductPage.parse(html: html, url: URL(string: "https://store.example.com/zoom/trick-worm.html")!)
        #expect(p.name == "Zoom Trick Worm 20pk")
        #expect(p.brand == "Zoom")
        #expect(p.image?.absoluteString == "https://store.example.com/image.php?path=zoom.jpg&nw=600")
        #expect(p.variants.count == 2)
        let gp = p.variants[0]
        #expect(gp.sku == "ZTW-GP")
        #expect(gp.upc == "74660000012")
        #expect(gp.title == "Green Pumpkin, 6.5\"")
        #expect(gp.image?.absoluteString == "https://store.example.com/image.php?path=gp.jpg&nw=600")
        #expect(p.variants[1].title == "Watermelon Red")
    }

    /// Only link-preview tags: still gets a name, photo and price.
    @Test func fallsBackToOpenGraph() async throws {
        let html = """
        <html><head><title>ignored</title>
        <meta property="og:site_name" content="Local Bait Co">
        <meta property="og:title" content="Senko 5in Watermelon | Local Bait Co">
        <meta property="og:image" content="//cdn.localbait.example/senko.jpg">
        <meta property="product:price:amount" content="8.99">
        </head></html>
        """
        let p = try await ProductPage.parse(html: html, url: URL(string: "https://localbait.example/senko")!)
        #expect(p.name == "Senko 5in Watermelon")
        #expect(p.image?.absoluteString == "https://cdn.localbait.example/senko.jpg")
        #expect(p.variants.first?.price == 8.99)
    }

    @Test func rejectsPagesWithoutProducts() async {
        await #expect(throws: ProductPageError.self) {
            try await ProductPage.parse(html: "<html><body><p>hello</p></body></html>", url: URL(string: "https://example.com")!)
        }
    }

    @Test func cleansTitles() {
        #expect(ProductPage.cleanTitle("Rage Craw - Bass Shop", site: "Bass Shop") == "Rage Craw")
        #expect(ProductPage.cleanTitle("Rage Craw | Bass Shop", site: nil) == "Rage Craw")
        #expect(ProductPage.cleanTitle("Rage Craw", site: "Bass Shop") == "Rage Craw")
    }

    @Test func searchesTheWeb() {
        #expect(WebSearch.url("Zoom Trick Worm 6.5\"").absoluteString == "x-web-search://?Zoom%20Trick%20Worm%206.5%22")
        #expect(WebSearch.url("A&B").absoluteString == "x-web-search://?A%26B")
    }
}

struct ShoppingListTests {
    private let entries = [
        ShoppingList.Entry(name: "Zoom Trick Worm", details: ["Watermelon Red", "6.5\""], quantity: 3, unit: "pack", onHand: 1,
                           price: 4.79, link: URL(string: "https://store.example.com/ztw"), category: .softPlastic),
        ShoppingList.Entry(name: "KVD 1.5 Squarebill", details: ["Strike King", "Sexy Shad"], quantity: 1, unit: "each", onHand: 2,
                           price: 7.49, link: nil, category: .hardBait),
    ]

    @Test func groupsByCategoryWithQuantities() {
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let text = ShoppingList.text(entries, options: .init(showOnHand: true), date: date)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[0] == "Tackle Shopping List")
        #expect(lines.contains("Soft plastics"))
        #expect(lines.contains("3 packs Zoom Trick Worm (Watermelon Red, 6.5\"), have 1"))
        #expect(lines.contains("1 × KVD 1.5 Squarebill (Strike King, Sexy Shad), have 2"))
        #expect(lines.firstIndex(of: "Soft plastics")! < lines.firstIndex(of: "Hard baits")!)
        #expect(!text.contains("$"))
        #expect(!text.contains("https://"))
    }

    @Test func optionalPricesAndLinks() {
        let text = ShoppingList.text(entries, options: .init(showOnHand: false, showPrices: true, showLinks: true))
        #expect(text.contains("3 packs Zoom Trick Worm (Watermelon Red, 6.5\"), $4.79 each\nhttps://store.example.com/ztw"))
        #expect(text.hasSuffix("Estimated total: $21.86"))
        #expect(!text.contains("have "))
    }
}

struct UpcLookupTests {
    @Test func parsesRelayResponse() {
        let json = #"{"code":"OK","items":[{"title":"Strike King Rage Craw","brand":"Strike King","images":["http://x/a.jpg","https://x/b.jpg"]}]}"#
        let s = UpcLookup.parse(Data(json.utf8))
        #expect(s?.name == "Strike King Rage Craw")
        #expect(s?.brand == "Strike King")
        #expect(s?.image?.absoluteString == "https://x/b.jpg")
        #expect(s?.category == .softPlastic)
        #expect(UpcLookup.parse(Data(#"{"items":[]}"#.utf8)) == nil)
    }
}

@MainActor
struct BackupTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Item.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    /// A backup exactly as the old web app wrote it.
    private let webBackup = """
    {"app":"TackleTracker","version":1,"exported_at":"2026-10-01T12:00:00.000Z",
     "items":[
      {"id":3,"name":"Zoom Trick Worm","brand":"Zoom","category":"soft_plastic","type":"Worm","color":"Green Pumpkin","size":"6.5\\"",
       "quantity":4,"unit":"pack","min_quantity":2,"location":"Bin 3","upc":"74660000012","sku":"ZTW-GP","price":4.79,
       "image_url":"img:abc","product_url":"https://store.example.com/x/ztw.html","specs":{},"notes":null,
       "on_list":false,"created_at":"2026-09-01T10:00:00.000Z","updated_at":"2026-09-02T10:00:00.000Z"},
      {"id":4,"name":"Curado DC","category":"reel","quantity":1,"unit":"each","min_quantity":0,"specs":{"Gear ratio":"7.4:1"},
       "image_url":"https://example.com/reel.jpg","on_list":true},
      {"id":5,"name":"","category":"bogus"}
     ],
     "images":{"abc":"data:image/jpeg;base64,/9j/AAAA"}}
    """

    @Test func restoresWebAppBackup() throws {
        let context = try makeContext()
        let file = try Backup.read(Data(webBackup.utf8))
        #expect(try Backup.restore(file, replace: false, into: context) == 2)

        let items = try context.fetch(FetchDescriptor<Item>()).sorted(by: Item.shelfOrder)
        #expect(items.count == 2)
        let worm = items[0]
        #expect(worm.name == "Zoom Trick Worm")
        #expect(worm.category == .softPlastic)
        #expect(worm.lureType == "Worm")
        #expect(worm.quantity == 4)
        #expect(worm.minQuantity == 2)
        #expect(worm.price == 4.79)
        #expect(worm.photo == Data(base64Encoded: "/9j/AAAA"))
        #expect(worm.createdAt == Backup.parseDate("2026-09-01T10:00:00.000Z"))
        let reel = items[1]
        #expect(reel.category == .reel)
        #expect(reel.specs["Gear ratio"] == "7.4:1")
        #expect(reel.imageURL == "https://example.com/reel.jpg")
        #expect(reel.onList)
    }

    @Test func roundTripsAndReplaces() throws {
        let context = try makeContext()
        try Backup.restore(Backup.read(Data(webBackup.utf8)), replace: false, into: context)
        let exported = try Backup.exportJSON(try context.fetch(FetchDescriptor<Item>()))

        try Backup.restore(Backup.read(exported), replace: true, into: context)
        let items = try context.fetch(FetchDescriptor<Item>()).sorted(by: Item.shelfOrder)
        #expect(items.map(\.name) == ["Zoom Trick Worm", "Curado DC"])
        #expect(items[0].photo == Data(base64Encoded: "/9j/AAAA"))
        #expect(items[0].upc == "74660000012")
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: Backup.ImportError.self) { try Backup.read(Data(#"{"hello":1}"#.utf8)) }
    }

    @Test func csvEscapesValues() throws {
        let context = try makeContext()
        let item = Item(name: "Worm, \"big\"", category: .softPlastic)
        context.insert(item)
        let csv = Backup.exportCSV([item])
        #expect(csv.contains(#""Worm, ""big""""#))
    }
}

@MainActor
struct ItemTests {
    @Test func lowAndSuggestions() {
        let it = Item(name: "Zoom Trick Worm")
        it.brand = "Zoom"
        it.color = "Green Pumpkin"
        it.quantity = 1
        it.minQuantity = 3
        #expect(it.isLow)
        #expect(it.suggestedBuy == 5)
        #expect(it.summary == "Green Pumpkin")
        #expect(it.shopURL.absoluteString == "x-web-search://?Zoom%20Trick%20Worm%20Green%20Pumpkin")
        it.productURL = "https://store.example.com/ztw"
        #expect(it.shopURL.absoluteString == "https://store.example.com/ztw")
        it.adjust(by: -5)
        #expect(it.quantity == 0)
    }
}
