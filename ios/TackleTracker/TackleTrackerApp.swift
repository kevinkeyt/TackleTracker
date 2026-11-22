import SwiftData
import SwiftUI

@main
struct TackleTrackerApp: App {
    let container: ModelContainer = {
        // Stored on this phone. To turn on iCloud sync later: add the iCloud (CloudKit) capability
        // with a container in Xcode and change this to `.automatic`.
        let config = ModelConfiguration(cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: Item.self, configurations: config)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedSampleData") { SampleData.seed(container.mainContext) }
            #endif
            return container
        } catch {
            fatalError("Couldn't open the tackle database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    @AppStorage("selectedTab") private var tab = AppTab.tackle

    var body: some View {
        TabView(selection: $tab) {
            Tab("Tackle", systemImage: "shippingbox", value: AppTab.tackle) { InventoryView() }
            Tab("Scan", systemImage: "barcode.viewfinder", value: AppTab.scan) { ScanView() }
            Tab("Reorder", systemImage: "cart", value: AppTab.reorder) { ReorderView() }
            Tab("More", systemImage: "ellipsis.circle", value: AppTab.more) { MoreView() }
        }
    }
}

enum AppTab: String {
    case tackle, scan, reorder, more
}

#if DEBUG
/// Launch with `-seedSampleData` (Debug builds only) to replace the list with a few sample items for trying out screens.
enum SampleData {
    static func seed(_ context: ModelContext) {
        try? context.delete(model: Item.self)
        func add(_ name: String, _ c: Category, brand: String? = nil, type: String? = nil, color: String? = nil, size: String? = nil,
                 qty: Int, min: Int = 0, loc: String? = nil, price: Double? = nil, unit: String = "pack", onList: Bool = false,
                 specs: [String: String] = [:]) {
            let it = Item(name: name, category: c)
            it.brand = brand; it.lureType = type; it.color = color; it.size = size; it.quantity = qty; it.minQuantity = min
            it.location = loc; it.price = price; it.unit = unit; it.onList = onList; it.specs = specs
            context.insert(it)
        }
        add("Zoom Trick Worm", .softPlastic, brand: "Zoom", type: "Worm", color: "Green Pumpkin", size: "6.5\"", qty: 4, min: 2, loc: "Bin 3", price: 4.79)
        add("Zoom Trick Worm", .softPlastic, brand: "Zoom", type: "Worm", color: "Watermelon Red", size: "6.5\"", qty: 1, min: 2, loc: "Bin 3", price: 4.79)
        add("Strike King Rage Craw", .softPlastic, brand: "Strike King", type: "Craw", color: "Black Blue Flake", qty: 3, loc: "Bin 4", price: 4.99)
        add("Strike King KVD 1.5 Squarebill", .hardBait, brand: "Strike King", type: "Crankbait", color: "Sexy Shad", qty: 2, loc: "Boat box", price: 7.49, unit: "each", onList: true)
        add("Gamakatsu EWG Worm Hook", .terminal, brand: "Gamakatsu", type: "Hooks", size: "4/0", qty: 2, min: 1, loc: "Bin 1", price: 5.99)
        add("Seaguar InvizX", .line, brand: "Seaguar", type: "Fluorocarbon", qty: 1, price: 34.99, unit: "spool", specs: ["Test (lb)": "15", "Yards": "200"])
        add("Shimano Curado DC", .reel, brand: "Shimano", type: "Baitcasting", qty: 1, price: 229.99, unit: "each", specs: ["Gear ratio": "7.4:1"])
        try? context.save()
    }
}
#endif
