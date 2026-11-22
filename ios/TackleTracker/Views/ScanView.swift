import SwiftData
import SwiftUI

enum ScanMode: String, CaseIterable, Identifiable {
    case lookup, add, remove

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lookup: "Look Up"
        case .add: "Add +1"
        case .remove: "Take Out −1"
        }
    }

    var hint: String {
        switch self {
        case .lookup: "Scan a package to see if you already own it, in the tackle room or in the store."
        case .add: "Each scan of something you own adds 1. New items stop so you can add them."
        case .remove: "Each scan takes 1 out of inventory, for loading the boat or using one up."
        }
    }
}

struct ScanResult: Identifiable {
    let id = UUID()
    let upc: String
    let owned: [Item]
    let suggestion: UpcSuggestion?

    var searchURL: URL { TackleWarehouse.searchURL(suggestion?.name ?? upc) }
}

struct ScanView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("scanMode") private var mode = ScanMode.lookup
    @State private var result: ScanResult?
    @State private var loading = false
    @State private var log: [LogEntry] = []
    @State private var last: (code: String, at: Date) = ("", .distantPast)
    @State private var newItem: ScanResult?
    @State private var notice: String?
    @State private var path = NavigationPath()

    struct LogEntry: Identifiable {
        let id = UUID()
        let item: Item
        let delta: Int
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("Scan Mode", selection: $mode) {
                        ForEach(ScanMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(mode.hint)
                }

                ScannerPanel(paused: result != nil || newItem != nil) { code, source in
                    Task { await handle(code, source: source) }
                }

                if loading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking Up…").foregroundStyle(.secondary)
                        }
                    }
                }

                if !log.isEmpty { sessionLog }
            }
            .navigationTitle("Scan")
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
            .sensoryFeedback(.success, trigger: log.count)
            .sheet(item: $result) { r in
                ScanResultSheet(result: r, mode: mode, onAdjust: { item, delta in apply(item, delta) }, onAddNew: {
                    result = nil
                    newItem = r
                }, onOpen: { item in
                    result = nil
                    path.append(item)
                })
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $newItem) { r in
                ItemEditView(mode: .new(upc: r.upc, suggestion: r.suggestion))
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var sessionLog: some View {
        let removed = log.filter { $0.delta < 0 }.count
        let added = log.filter { $0.delta > 0 }.count
        return Section {
            ForEach(log) { e in
                HStack(spacing: 12) {
                    Thumb(item: e.item, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(e.delta < 0 ? "Took out 1" : "Added 1")\(e.item.color.map { " · \($0)" } ?? "") · \(e.item.quantity) left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Undo") { undo(e) }
                        .buttonStyle(.borderless)
                }
                .swipeActions {
                    Button("Undo") { undo(e) }.tint(.blue)
                }
            }
        } header: {
            Text("This Session")
        } footer: {
            Text([removed > 0 ? "\(removed) taken out" : nil, added > 0 ? "\(added) added" : nil].compactMap { $0 }.joined(separator: ", "))
        }
    }

    private func handle(_ code: String, source: ScanSource) async {
        // The camera reports the same barcode many times a second; act once per package.
        if source == .camera && code == last.code && Date.now.timeIntervalSince(last.at) < 2.5 { return }
        last = (code, .now)
        guard !loading, result == nil, newItem == nil else { return }
        guard let upc = UPC.normalize(code) else {
            notice = "No digits in that barcode"
            return
        }
        loading = true
        defer { loading = false }
        let owned = ((try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.upc == upc }))) ?? [])
            .sorted(by: Item.shelfOrder)
        let only = owned.count == 1 ? owned[0] : nil
        if mode == .add, let only {
            apply(only, 1)
        } else if mode == .remove, let only, only.quantity > 0 {
            apply(only, -1)
        } else {
            let suggestion = owned.isEmpty ? await UpcLookup.lookup(upc) : nil
            result = ScanResult(upc: upc, owned: owned, suggestion: suggestion)
        }
    }

    private func apply(_ item: Item, _ delta: Int) {
        item.adjust(by: delta)
        log.insert(LogEntry(item: item, delta: delta), at: 0)
    }

    private func undo(_ entry: LogEntry) {
        entry.item.adjust(by: -entry.delta)
        log.removeAll { $0.id == entry.id }
    }
}

private struct ScanResultSheet: View {
    let result: ScanResult
    let mode: ScanMode
    let onAdjust: (Item, Int) -> Void
    let onAddNew: () -> Void
    let onOpen: (Item) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if result.owned.isEmpty {
                    Section {
                        if let s = result.suggestion {
                            HStack(spacing: 12) {
                                Thumb(photo: nil, imageURL: s.image?.absoluteString)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name ?? "").font(.headline)
                                    Text([s.brand, s.color, s.size].compactMap { $0 }.joined(separator: " · "))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Label("Not in Your Tackle", systemImage: "plus.circle")
                    } footer: {
                        Text(result.suggestion == nil
                             ? "UPC \(result.upc). No product info was found for this barcode, but you can still add it and fill in the details."
                             : "UPC \(result.upc)")
                    }
                } else {
                    let total = result.owned.reduce(0) { $0 + $1.quantity }
                    Section {
                        ForEach(result.owned) { it in
                            Button { onOpen(it) } label: { ItemRow(item: it) }
                                .foregroundStyle(.primary)
                            Stepper("On hand: \(it.quantity)", value: Binding(
                                get: { it.quantity }, set: { onAdjust(it, $0 - it.quantity) }
                            ), in: 0...9_999)
                        }
                    } header: {
                        if total > 0 {
                            Label("You Have This: \(total) on Hand", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("None on Hand", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    } footer: {
                        if total == 0 { Text("You've had this before, but they're all used or out.") }
                    }
                }

                Section {
                    Button(result.owned.isEmpty ? "Add to My Tackle" : "Add as Separate Item", action: onAddNew)
                    Link(destination: result.searchURL) {
                        Label("Search Tackle Warehouse", systemImage: "safari")
                    }
                }
            }
            .navigationTitle(result.owned.isEmpty ? "New Barcode" : "Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
