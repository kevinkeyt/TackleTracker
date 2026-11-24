import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MoreView: View {
    @Query private var items: [Item]
    @Environment(\.modelContext) private var context
    @AppStorage(Backup.lastKey) private var lastBackup: Double = 0
    @AppStorage(UpcLookup.relayKey) private var relay = UpcLookup.defaultRelay
    @State private var relayDraft = ""
    @State private var backupDocument: JSONDocument?
    @State private var importing = false
    @State private var pendingRestore: BackupFile?
    @State private var message: (title: String, detail: String)?

    var body: some View {
        NavigationStack {
            Form {
                statsSection
                backupSection
                relaySection
                Section("Tips") {
                    Label("On the Scan tab, Add +1 tallies packages as you shelve them, and Take Out −1 removes them as they go in the boat.", systemImage: "barcode.viewfinder")
                    Label("Swipe right on an item to add one, or left to take one out.", systemImage: "hand.draw")
                    Label("Filling in from a product link, barcode lookup and Shop need internet. Everything else works offline.", systemImage: "wifi.slash")
                }
                .font(.subheadline)
            }
            .navigationTitle("More")
            .fileExporter(isPresented: Binding(get: { backupDocument != nil }, set: { if !$0 { backupDocument = nil } }),
                          document: backupDocument, contentType: .json, defaultFilename: Backup.backupFilename) { result in
                switch result {
                case .success: lastBackup = Date.now.timeIntervalSince1970
                case .failure(let error): message = ("Backup Failed", error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                readBackup(result)
            }
            .confirmationDialog("Restore \(pendingRestore?.items.count ?? 0) items?", isPresented: Binding(
                get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }
            ), titleVisibility: .visible) {
                Button("Replace Everything on This iPhone", role: .destructive) { restore(replace: true) }
                Button("Add to What I Have") { restore(replace: false) }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: {
                Text("Replace deletes your current list first. Add keeps it and adds the backup's items alongside.")
            }
            .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message?.detail ?? "")
            }
            .onAppear { relayDraft = relay }
        }
    }

    // MARK: Sections

    private var statsSection: some View {
        let byCategory = Dictionary(grouping: items, by: \.category)
        let units = items.reduce(0) { $0 + $1.quantity }
        let value = items.reduce(0.0) { $0 + Double($1.quantity) * ($1.price ?? 0) }
        return Section("Your Tackle") {
            LabeledContent("Items", value: items.count.formatted())
            LabeledContent("Packs and pieces", value: units.formatted())
            LabeledContent("Estimated value", value: Money.whole(value))
            ForEach(Category.allCases.filter { byCategory[$0] != nil }) { c in
                let group = byCategory[c] ?? []
                let low = group.filter(\.needsReorder).count
                LabeledContent {
                    Text("\(group.count) item\(group.count == 1 ? "" : "s"), \(group.reduce(0) { $0 + $1.quantity }) on hand")
                } label: {
                    Text(c.label)
                    if low > 0 { Text("\(low) to reorder") }
                }
            }
        }
    }

    private var backupSection: some View {
        let days = lastBackup > 0 ? Backup.daysSinceBackup : nil
        let overdue = days == nil || days! >= Backup.remindDays
        return Section {
            LabeledContent("Last backup") {
                Text(days.map { $0 == 0 ? "Today" : "\($0) day\($0 == 1 ? "" : "s") ago" } ?? "Never")
                    .foregroundStyle(overdue ? .orange : .secondary)
            }
            Button {
                do {
                    backupDocument = JSONDocument(data: try Backup.exportJSON(items))
                } catch {
                    message = ("Backup Failed", error.localizedDescription)
                }
            } label: {
                Label("Back Up Now", systemImage: "externaldrive.badge.icloud")
            }
            ShareLink(item: CSVFile(text: Backup.exportCSV(items), filename: Backup.csvFilename),
                      preview: SharePreview(Backup.csvFilename)) {
                Label("Export Spreadsheet (CSV)", systemImage: "tablecells")
            }
            Button {
                importing = true
            } label: {
                Label("Restore from Backup…", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Your tackle is stored only on this iPhone. Save a backup to Files (iCloud Drive) now and then so a lost or reset phone doesn't take it with it. Backups from the old web app can be restored here too.")
        }
    }

    private var relaySection: some View {
        Section {
            TextField("https://upc-relay.you.workers.dev", text: $relayDraft)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save") { saveRelay() }
                .disabled(relayDraft.trimmingCharacters(in: .whitespaces) == relay)
        } header: {
            Text("Barcode Lookup")
        } footer: {
            Text("Fills in the name of packages you haven't added yet, through a small online lookup service. Clear the address to turn it off; scanning still finds everything you own.")
        }
    }

    // MARK: Actions

    private func readBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try Backup.read(Data(contentsOf: url))
        } catch {
            message = ("Restore Failed", error.localizedDescription)
        }
    }

    private func restore(replace: Bool) {
        guard let file = pendingRestore else { return }
        pendingRestore = nil
        do {
            let n = try Backup.restore(file, replace: replace, into: context)
            message = ("Restore Complete", "Restored \(n) item\(n == 1 ? "" : "s").")
        } catch {
            message = ("Restore Failed", error.localizedDescription)
        }
    }

    private func saveRelay() {
        let value = relayDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && !value.hasPrefix("https://") {
            message = ("Invalid Address", "The relay address should start with https://")
            return
        }
        relay = value
        relayDraft = value
    }
}
