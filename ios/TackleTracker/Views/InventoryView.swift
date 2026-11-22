import SwiftData
import SwiftUI

struct InventoryView: View {
    @Query private var allItems: [Item]
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var category: Category?
    @State private var lowOnly = false
    @State private var adding = false
    @State private var deleting: Item?
    @State private var path = NavigationPath()
    @AppStorage("selectedTab") private var tab = AppTab.tackle
    @AppStorage(Backup.lastKey) private var lastBackup: Double = 0 // redraw when a backup is made

    private var shown: [Item] {
        let words = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return allItems.filter { it in
            if lowOnly && !it.needsReorder { return false }
            if let category, it.category != category { return false }
            let hay = it.searchText
            return words.allSatisfy { hay.contains($0) }
        }
        .sorted(by: Item.shelfOrder)
    }

    private var filtering: Bool { category != nil || lowOnly }

    var body: some View {
        NavigationStack(path: $path) {
            let shown = shown
            List {
                if needsBackup {
                    Section { backupReminder }
                }
                ForEach(Category.allCases) { c in
                    let group = shown.filter { $0.category == c }
                    if !group.isEmpty {
                        Section(c.label) {
                            ForEach(group) { it in
                                NavigationLink(value: it) { ItemRow(item: it) }
                                    .quantityActions(it) { deleting = it }
                            }
                        }
                    }
                }
            }
            .overlay { emptyState(shown: shown) }
            .navigationTitle("Tackle")
            .searchable(text: $search, prompt: "Name, color, brand, bin")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Label("Add Item", systemImage: "plus") }
                }
            }
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
            .sheet(isPresented: $adding) {
                ItemEditView(mode: .new()) { saved in path.append(saved) }
            }
            .confirmationDialog("Delete \(deleting?.label ?? "")?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let deleting { context.delete(deleting) }
                }
            }
        }
    }

    private var filterMenu: some View {
        let counts = Dictionary(grouping: allItems, by: \.category).mapValues(\.count)
        return Menu {
            Picker("Category", selection: $category) {
                Text("All Categories").tag(Category?.none)
                ForEach(Category.allCases.filter { counts[$0] != nil }) { c in
                    Text("\(c.label) (\(counts[c] ?? 0))").tag(Optional(c))
                }
            }
            Toggle(isOn: $lowOnly) {
                Label("Needs Reordering", systemImage: "cart")
            }
        } label: {
            Label("Filter", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private var needsBackup: Bool {
        allItems.count >= 5 && (Backup.daysSinceBackup ?? .max) >= Backup.remindDays
    }

    private var backupReminder: some View {
        Button {
            tab = .more
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Backup.daysSinceBackup.map { "Last backup was \($0) days ago" } ?? "Back up your tackle")
                        .foregroundStyle(Color(.label))
                    Text("Your list is stored only on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            } icon: {
                Image(systemName: "exclamationmark.icloud")
            }
        }
    }

    @ViewBuilder private func emptyState(shown: [Item]) -> some View {
        if allItems.isEmpty {
            ContentUnavailableView {
                Label("No Tackle Yet", systemImage: "shippingbox")
            } description: {
                Text("Scan a package's barcode, or paste a Tackle Warehouse link to add your first item.")
            } actions: {
                Button("Scan a Barcode") { tab = .scan }
                    .buttonStyle(.borderedProminent)
                Button("Add by Hand") { adding = true }
            }
        } else if shown.isEmpty {
            if search.isEmpty {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing matches the current filter.")
                } actions: {
                    Button("Clear Filter") {
                        category = nil
                        lowOnly = false
                    }
                }
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}
