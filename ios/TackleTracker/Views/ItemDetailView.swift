import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var addingColor = false
    @State private var confirmDelete = false

    var body: some View {
        // Right after a delete the view can redraw once more before it pops; don't touch the deleted item.
        if item.isDeleted || item.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Thumb(item: item, size: 160)
                    Text(item.name).font(.title2.bold()).multilineTextAlignment(.center)
                    if !item.summary.isEmpty {
                        Text(item.summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                Stepper(value: quantity, in: 0...9_999) {
                    LabeledContent("On hand", value: "\(item.quantity) \(Units.label(item.unit, count: item.quantity))")
                }
                .sensoryFeedback(.selection, trigger: item.quantity)
            } footer: {
                if item.minQuantity > 0 {
                    if item.isLow {
                        Label("Running low. Reorder at \(item.minQuantity).", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Reorder at \(item.minQuantity).")
                    }
                }
            }

            Section {
                Link(destination: item.shopURL) {
                    Label(item.productURL != nil ? "Buy More" : "Find on Tackle Warehouse", systemImage: "safari")
                }
                Toggle(isOn: Binding(get: { item.onList }, set: { item.onList = $0; item.updatedAt = .now })) {
                    Label("On Reorder List", systemImage: "cart")
                }
                Button { addingColor = true } label: {
                    Label("Add Another Color", systemImage: "plus.square.on.square")
                }
            }

            Section("Details") {
                ForEach(details, id: \.0) { key, value in
                    LabeledContent(key) {
                        Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Delete Item", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            ItemEditView(mode: .edit(item))
        }
        .sheet(isPresented: $addingColor) {
            ItemEditView(mode: .copy(item))
        }
        .confirmationDialog("Delete \(item.label)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                context.delete(item)
            }
        }
    }

    private var quantity: Binding<Int> {
        Binding(get: { item.quantity }, set: { item.adjust(by: $0 - item.quantity) })
    }

    private var details: [(String, String)] {
        var rows: [(String, String?)] = [
            ("Category", item.category.label),
            ("Type", item.lureType),
            ("Brand", item.brand),
            ("Color", item.color),
            ("Size", item.size),
            ("Kept in", item.location),
        ]
        let specKeys = item.category.specFields + item.specs.keys.filter { !item.category.specFields.contains($0) }.sorted()
        rows += specKeys.map { ($0, item.specs[$0]) }
        rows += [
            ("Price", item.price.map { Money.string($0) }),
            ("UPC", item.upc),
            ("SKU", item.sku),
            ("Notes", item.notes),
        ]
        return rows.compactMap { k, v in v.nilIfBlank.map { (k, $0) } }
    }
}
