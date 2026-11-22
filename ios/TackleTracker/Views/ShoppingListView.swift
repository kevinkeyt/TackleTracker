import SwiftData
import SwiftUI

/// Review what to buy, then share the list to Notes (or Messages, Mail…) for a trip to the tackle store.
struct ShoppingListView: View {
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var excluded: Set<PersistentIdentifier> = []
    @State private var quantities: [PersistentIdentifier: Int] = [:]
    @AppStorage("shoppingList.showOnHand") private var showOnHand = true
    @AppStorage("shoppingList.showPrices") private var showPrices = false
    @AppStorage("shoppingList.showLinks") private var showLinks = false

    private var included: [Item] { items.filter { !excluded.contains($0.persistentModelID) } }

    private var text: String {
        ShoppingList.text(included.map(entry), options: .init(showOnHand: showOnHand, showPrices: showPrices, showLinks: showLinks))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(items) { row($0) }
                } header: {
                    Text("Items")
                } footer: {
                    Text("Tap an item to leave it off the list.")
                }

                Section("Include") {
                    Toggle("What I Have on Hand", isOn: $showOnHand)
                    Toggle("Prices", isOn: $showPrices)
                    Toggle("Product Links", isOn: $showLinks)
                }

                Section {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Tap Share and choose Notes to save the list as a note. In Notes, select the items and tap the checklist button to check them off in the store.")
                }
            }
            .navigationTitle("Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text, subject: Text("Tackle Shopping List"), preview: SharePreview("Tackle Shopping List")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(included.isEmpty)
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        let id = item.persistentModelID
        let on = !excluded.contains(id)
        return HStack(spacing: 12) {
            Button {
                if on { excluded.insert(id) } else { excluded.remove(id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).foregroundStyle(on ? .primary : .secondary)
                        Text(([item.summary.nilIfBlank].compactMap { $0 } + ["Have \(item.quantity)"]).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            Spacer()
            if on {
                Text("\(quantity(item))").monospacedDigit()
                Stepper("Quantity", value: Binding(get: { quantity(item) }, set: { quantities[id] = $0 }), in: 1...999)
                    .labelsHidden()
            }
        }
    }

    private func quantity(_ item: Item) -> Int {
        quantities[item.persistentModelID] ?? item.suggestedBuy
    }

    private func entry(_ item: Item) -> ShoppingList.Entry {
        let brand = item.brand.nilIfBlank.flatMap { item.name.lowercased().hasPrefix($0.lowercased()) ? nil : $0 }
        return ShoppingList.Entry(
            name: item.name,
            details: [brand, item.color, item.size].compactMap { $0.nilIfBlank },
            quantity: quantity(item),
            unit: item.unit,
            onHand: item.quantity,
            price: item.price,
            link: item.productURL.flatMap { ProductPage.link(from: $0) },
            category: item.category
        )
    }
}
