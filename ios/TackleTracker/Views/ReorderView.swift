import SwiftData
import SwiftUI

struct ReorderView: View {
    @Query private var allItems: [Item]
    @State private var receiving: Item?
    @State private var receivedCount = ""
    @State private var showingList = false
    @Environment(\.openURL) private var openURL

    private var items: [Item] { allItems.filter(\.needsReorder).sorted(by: Item.shelfOrder) }

    var body: some View {
        NavigationStack {
            let items = items
            let total = items.reduce(0.0) { $0 + ($1.price ?? 0) * Double($1.suggestedBuy) }
            List {
                Section {
                    ForEach(items) { it in
                        NavigationLink(value: it) {
                            ItemRow(item: it, trailing: "Buy \(it.suggestedBuy)")
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { startReceiving(it) } label: { Label("Got It", systemImage: "shippingbox") }
                                .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { openURL(it.shopURL) } label: { Label("Shop", systemImage: "safari") }
                                .tint(.blue)
                            if it.onList && !it.isLow {
                                Button { it.onList = false } label: { Label("Remove", systemImage: "cart.badge.minus") }
                            }
                        }
                        .contextMenu {
                            Link(destination: it.shopURL) { Label("Shop", systemImage: "safari") }
                            Button { startReceiving(it) } label: { Label("Got It", systemImage: "shippingbox") }
                            if it.onList && !it.isLow {
                                Button { it.onList = false } label: { Label("Remove from List", systemImage: "cart.badge.minus") }
                            }
                        }
                    }
                } footer: {
                    if !items.isEmpty {
                        Text(total > 0
                             ? "About \(Money.string(total)) to restock everything at last known prices. Swipe right when an order arrives."
                             : "Swipe right when an order arrives.")
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Nothing to Reorder", systemImage: "cart",
                                           description: Text("Items show up here when they drop to their reorder level, or when you add them to the list yourself."))
                }
            }
            .navigationTitle("Reorder")
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
            .toolbar {
                if !items.isEmpty {
                    Button { showingList = true } label: {
                        Label("Shopping List", systemImage: "list.bullet.clipboard")
                    }
                }
            }
            .sheet(isPresented: $showingList) {
                ShoppingListView(items: items)
            }
            .alert(receivedTitle, isPresented: Binding(get: { receiving != nil }, set: { if !$0 { receiving = nil } })) {
                TextField("How many", text: $receivedCount).keyboardType(.numberPad)
                Button("Add") { received() }
                Button("Cancel", role: .cancel) { receiving = nil }
            } message: {
                Text("They'll be added to what you have and taken off the list.")
            }
        }
    }

    private var receivedTitle: String {
        guard let it = receiving else { return "" }
        return "How many \(Units.label(it.unit, count: 2)) of \(it.label) came in?"
    }

    private func startReceiving(_ it: Item) {
        receivedCount = String(it.suggestedBuy)
        receiving = it
    }

    private func received() {
        guard let it = receiving, let n = Int(receivedCount.filter(\.isASCIIDigit)), n > 0 else { return }
        it.adjust(by: n)
        it.onList = false
        receiving = nil
    }
}
