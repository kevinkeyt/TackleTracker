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

struct TackleWarehouseTests {
    @Test func acceptsOnlyProductLinks() throws {
        let url = try TackleWarehouse.productURL(from: " http://tacklewarehouse.com/Zoom_Trick_Worm/descpage-ZTW.html#reviews ")
        #expect(url.absoluteString == "https://www.tacklewarehouse.com/Zoom_Trick_Worm/descpage-ZTW.html")
        #expect(throws: TWError.self) { try TackleWarehouse.productURL(from: "https://example.com/descpage-X.html") }
        #expect(throws: TWError.self) { try TackleWarehouse.productURL(from: "https://www.tacklewarehouse.com/catpage-soft.html") }
    }

    @Test func parsesProductPage() async throws {
        let html = """
        <html><head><title>Zoom Trick Worm 20pk - Tackle Warehouse</title>
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
        let url = URL(string: "https://www.tacklewarehouse.com/Zoom_Trick_Worm/descpage-ZTW.html")!
        let p = try await TackleWarehouse.parse(html: html, url: url)
        #expect(p.name == "Zoom Trick Worm 20pk")
        #expect(p.brand == "Zoom")
        #expect(p.category == .softPlastic)
        #expect(p.image?.absoluteString.contains("nw=600") == true)
        #expect(p.variants.count == 2)
        let gp = p.variants[0]
        #expect(gp.sku == "ZTW-GP")
        #expect(gp.price == 4.79)
        #expect(gp.upc == "74660000012")
        #expect(gp.color == "Green Pumpkin")
        #expect(gp.size == "6.5\"")
        #expect(gp.inStock == "In Stock")
        #expect(gp.image?.absoluteString == "https://www.tacklewarehouse.com/image.php?path=gp.jpg&nw=600")
        #expect(p.variants[1].title == "Watermelon Red")
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
       "image_url":"img:abc","product_url":"https://www.tacklewarehouse.com/x/descpage-ZTW.html","specs":{},"notes":null,
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
        #expect(it.shopURL.absoluteString.contains("searchtext=Zoom%20Trick%20Worm%20Green%20Pumpkin"))
        it.adjust(by: -5)
        #expect(it.quantity == 0)
    }
}
