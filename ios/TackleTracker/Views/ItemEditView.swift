import PhotosUI
import SwiftData
import SwiftUI

/// Add or edit an item. Everything is edited on a draft and written to the store only on Save.
struct ItemEditView: View {
    enum Mode {
        /// A new item, optionally from a scan.
        case new(upc: String? = nil, suggestion: UpcSuggestion? = nil)
        case edit(Item)
        /// "Add another color": same product, the color-specific fields cleared.
        case copy(Item)
    }

    let mode: Mode
    var onSaved: (Item) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [Item]

    @State private var draft: Draft
    @State private var error: String?
    @State private var scanningUPC = false
    @State private var takingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var imageBusy = false

    @State private var linkText: String
    @State private var product: ProductInfo?
    @State private var linkLoading = false
    @State private var choosingVariant = false

    init(mode: Mode, onSaved: @escaping (Item) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
        let draft = Draft(mode)
        _draft = State(initialValue: draft)
        _linkText = State(initialValue: draft.productURL ?? "")
    }

    private var editingItem: Item? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                linkSection
                noticesSection
                photoSection
                mainSection
                quantitySection
                if !draft.category.specFields.isEmpty { specsSection }
                codesSection
                Section("Notes") {
                    TextField("Rigging, what it works on, etc.", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("On Reorder List", isOn: $draft.onList)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(editingItem == nil ? "Add tackle" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingItem == nil ? "Add" : "Save", action: save)
                        .disabled(imageBusy || draft.name.nilIfBlank == nil)
                }
            }
            .sheet(isPresented: $scanningUPC) {
                NavigationStack {
                    List {
                        ScannerPanel { code, _ in
                            draft.upc = code
                            scanningUPC = false
                        }
                    }
                    .navigationTitle("Scan UPC")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanningUPC = false } }
                    }
                }
            }
            .sheet(isPresented: $takingPhoto) {
                ImagePicker(source: .camera) { image in
                    Task { await setPhoto(Photos.jpeg(from: image)) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickedPhoto) {
                guard let pickedPhoto else { return }
                Task {
                    imageBusy = true
                    var jpeg: Data?
                    if let data = try? await pickedPhoto.loadTransferable(type: Data.self) {
                        jpeg = await Photos.jpeg(from: data)
                    }
                    await setPhoto(jpeg)
                    self.pickedPhoto = nil
                }
            }
            .navigationDestination(isPresented: $choosingVariant) {
                if let product {
                    VariantList(product: product) { v in
                        choosingVariant = false
                        Task { await apply(product, v) }
                    }
                }
            }
            .task { await prefill() }
        }
    }

    // MARK: Sections

    private var linkSection: some View {
        Section {
            HStack {
                TextField("Product link", text: $linkText, prompt: Text("Paste a product page link"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await loadLink() } }
                if linkText.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        guard let clip = strings.first else { return }
                        linkText = clip
                        if ProductPage.link(from: clip) != nil { Task { await loadLink(clip) } }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                } else if linkLoading {
                    ProgressView()
                } else {
                    Button("Load") { Task { await loadLink() } }
                        .buttonStyle(.borderless)
                }
            }
            if let product, product.variants.count > 1 {
                Button { choosingVariant = true } label: {
                    LabeledContent("Choose Option", value: "\(product.variants.count) options")
                }
                .foregroundStyle(.primary)
            }
            Link(destination: WebSearch.url([draft.brand, draft.name].compactMap(\.nilIfBlank).joined(separator: " ").nilIfBlank ?? draft.upc)) {
                Label("Search the Web", systemImage: "magnifyingglass")
            }
        } header: {
            Text("Fill In from a Product Link")
        } footer: {
            Text("Paste the link to the product on any store's website. Whatever the page lists, like the name, photo, price and UPC, is filled in, and the link is saved so you can reorder.")
        }
    }

    @ViewBuilder private var noticesSection: some View {
        let others = allItems.filter { $0.persistentModelID != editingItem?.persistentModelID }
        let upc = UPC.normalize(draft.upc)
        let sameUPC = upc.map { u in others.filter { $0.upc == u } } ?? []
        if !sameUPC.isEmpty {
            Section {
                ForEach(sameUPC) { it in
                    ItemRow(item: it)
                }
            } header: {
                Label("You Already Have This Barcode", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } else {
            let similar = similarItems(others)
            if !similar.isEmpty {
                Section("Similar items you have") {
                    ForEach(similar) { it in
                        ItemRow(item: it)
                    }
                }
            }
        }
    }

    private func similarItems(_ others: [Item]) -> [Item] {
        let name = draft.name.lowercased()
        guard name.trimmingCharacters(in: .whitespaces).count >= 3 else { return [] }
        let words = name.split(whereSeparator: \.isWhitespace).filter { $0.count > 2 }
        let color = draft.color.nilIfBlank?.lowercased()
        return Array(others.filter { it in
            words.allSatisfy { it.name.lowercased().contains($0) } && (color == nil || it.color?.lowercased() == color)
        }.prefix(4))
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Thumb(photo: draft.photo, imageURL: draft.imageURL, size: 88)
                    if imageBusy { ProgressView() }
                }
                Menu {
                    Button { takingPhoto = true } label: { Label("Take Photo", systemImage: "camera") }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    if draft.photo != nil || draft.imageURL != nil {
                        Button(role: .destructive) {
                            draft.photo = nil
                            draft.imageURL = nil
                        } label: { Label("Remove Photo", systemImage: "trash") }
                    }
                } label: {
                    Text(draft.photo == nil && draft.imageURL == nil ? "Add Photo" : "Edit Photo")
                }
            }
        }
    }

    private var mainSection: some View {
        Section {
            TextField("Name", text: $draft.name, prompt: Text("Name, e.g. Zoom Trick Worm"))
            Picker("Category", selection: $draft.category) {
                ForEach(Category.allCases) { Text($0.label).tag($0) }
            }
            SuggestField(title: "Type", text: $draft.lureType, options: draft.category.types)
            SuggestField(title: "Brand", text: $draft.brand, options: unique(\.brand))
            TextField("Color", text: $draft.color, prompt: Text("Color, e.g. Green Pumpkin"))
            TextField("Size", text: $draft.size, prompt: Text("Size or weight, e.g. 3/8 oz"))
            SuggestField(title: "Location", text: $draft.location, options: unique(\.location))
        }
    }

    private var quantitySection: some View {
        Section {
            Stepper("On hand: \(draft.quantity)", value: $draft.quantity, in: 0...9_999)
            Picker("Unit", selection: $draft.unit) {
                ForEach(Units.all, id: \.self) { Text(Units.label($0, count: draft.quantity).capitalized).tag($0) }
            }
            Stepper("Reorder at: \(draft.minQuantity)", value: $draft.minQuantity, in: 0...9_999)
        } footer: {
            Text(draft.minQuantity > 0 ? "Shows on the Reorder tab when you're down to \(draft.minQuantity)." : "Set Reorder at above 0 to get flagged when you're running low.")
        }
    }

    private var specsSection: some View {
        Section(draft.category.label) {
            ForEach(draft.category.specFields, id: \.self) { key in
                LabeledContent(key) {
                    TextField(key, text: Binding(
                        get: { draft.specs[key] ?? "" },
                        set: { draft.specs[key] = $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var codesSection: some View {
        Section {
            HStack {
                TextField("UPC", text: $draft.upc).keyboardType(.numberPad)
                Button { scanningUPC = true } label: { Label("Scan UPC", systemImage: "barcode.viewfinder").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
            }
            HStack {
                Text("$").foregroundStyle(.secondary)
                TextField("Price", text: $draft.priceText).keyboardType(.decimalPad)
            }
            TextField("Product link", text: $draft.productURLText, prompt: Text("Product link for reordering"))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !draft.sku.isEmpty {
                LabeledContent("SKU", value: draft.sku)
            }
        }
    }

    private func unique(_ key: KeyPath<Item, String?>) -> [String] {
        Array(Set(allItems.compactMap { $0[keyPath: key].nilIfBlank })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Actions

    private func prefill() async {
        switch mode {
        case .copy(let source):
            // Same product family: jump straight to its color list so adding another color is two taps.
            if let link = source.productURL { await loadLink(link) }
        case .new(_, let suggestion):
            if let image = suggestion?.image { await setRemoteImage(image) }
        case .edit:
            break
        }
    }

    private func loadLink(_ link: String? = nil) async {
        let text = (link ?? linkText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        error = nil
        guard let url = ProductPage.link(from: text) else {
            error = ProductPageError.invalidLink.localizedDescription
            return
        }
        // Whatever the page turns out to say, the link is where to reorder.
        draft.productURLText = url.absoluteString
        linkLoading = true
        defer { linkLoading = false }
        do {
            let info = try await ProductPage.fetch(url.absoluteString)
            product = info
            draft.productURLText = info.url.absoluteString
            if let upc = UPC.normalize(draft.upc), let match = info.variants.first(where: { $0.upc == upc }) {
                await apply(info, match)
            } else if info.variants.count == 1 {
                await apply(info, info.variants[0])
            } else {
                fillProduct(info)
                if let image = info.image, draft.photo == nil, draft.imageURL == nil { await setRemoteImage(image) }
                if info.variants.count > 1 { choosingVariant = true }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Product-level details, without overwriting what's already typed in when editing.
    private func fillProduct(_ info: ProductInfo) {
        let editing = editingItem != nil && draft.name.nilIfBlank != nil
        if !editing || draft.name.nilIfBlank == nil, info.name.nilIfBlank != nil { draft.name = info.name }
        if draft.brand.nilIfBlank == nil, let brand = info.brand { draft.brand = brand }
        if !editing && info.category != .other { draft.category = info.category }
    }

    private func apply(_ info: ProductInfo, _ v: ProductVariant) async {
        fillProduct(info)
        draft.color = v.color ?? draft.color
        draft.size = v.size ?? draft.size
        draft.sku = v.sku ?? draft.sku
        if let price = v.price { draft.priceText = String(format: "%.2f", price) }
        draft.upc = v.upc ?? draft.upc
        draft.productURLText = info.url.absoluteString
        for (k, value) in v.styles where k != "Color" { draft.specs[k] = value }
        product = nil
        if let image = v.image ?? info.image { await setRemoteImage(image) }
    }

    private func setRemoteImage(_ url: URL) async {
        imageBusy = true
        defer { imageBusy = false }
        if let data = await Photos.download(url) {
            draft.photo = data
            draft.imageURL = nil
        } else {
            // The site wouldn't hand over the file; show it from the web instead.
            draft.photo = nil
            draft.imageURL = url.absoluteString
        }
    }

    private func setPhoto(_ data: Data?) async {
        imageBusy = false
        guard let data else {
            error = "Couldn't read that photo"
            return
        }
        draft.photo = data
        draft.imageURL = nil
    }

    private func save() {
        guard draft.name.nilIfBlank != nil else {
            error = "Give it a name"
            return
        }
        let item = editingItem ?? Item()
        draft.write(to: item)
        if editingItem == nil { context.insert(item) }
        try? context.save()
        dismiss()
        onSaved(item)
    }
}

/// Every color/size a product page offers, as a searchable list.
private struct VariantList: View {
    let product: ProductInfo
    let onPick: (ProductVariant) -> Void
    @State private var filter = ""

    var body: some View {
        let shown = product.variants.filter {
            filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.title.localizedCaseInsensitiveContains(filter)
        }
        List(shown) { v in
            Button { onPick(v) } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: v.image) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { Color(.secondarySystemFill) }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title).foregroundStyle(.primary)
                        if let stock = v.inStock {
                            Text(stock).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Money.string(v.price)).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Options")
        .overlay {
            if shown.isEmpty { ContentUnavailableView.search(text: filter) }
        }
    }
}

/// A text field with a menu of values used before.
private struct SuggestField: View {
    let title: String
    @Binding var text: String
    let options: [String]

    var body: some View {
        HStack {
            TextField(title, text: $text)
            if !options.isEmpty {
                Menu {
                    ForEach(options, id: \.self) { o in Button(o) { text = o } }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .accessibilityLabel("Choose \(title.components(separatedBy: " (").first ?? title)")
            }
        }
    }
}

/// Plain-value copy of an item for the form; empty strings mean "not set".
struct Draft {
    var name = ""
    var brand = ""
    var category = Category.softPlastic
    var lureType = ""
    var color = ""
    var size = ""
    var quantity = 1
    var unit = "pack"
    var minQuantity = 0
    var location = ""
    var upc = ""
    var sku = ""
    var priceText = ""
    var photo: Data?
    var imageURL: String?
    var productURLText = ""
    var specs: [String: String] = [:]
    var notes = ""
    var onList = false

    var productURL: String? { productURLText.nilIfBlank }

    init() {}

    init(_ mode: ItemEditView.Mode) {
        self.init()
        switch mode {
        case .new(let upc, let s):
            self.upc = upc ?? ""
            name = s?.name ?? ""
            brand = s?.brand ?? ""
            color = s?.color ?? ""
            size = s?.size ?? ""
            if let c = s?.category, c != .other { category = c }
        case .edit(let item):
            self = Draft(item: item)
        case .copy(let item):
            self = Draft(item: item)
            color = ""
            upc = ""
            sku = ""
            photo = nil
            imageURL = nil
            quantity = 1
            onList = false
        }
    }

    private init(item it: Item) {
        name = it.name
        brand = it.brand ?? ""
        category = it.category
        lureType = it.lureType ?? ""
        color = it.color ?? ""
        size = it.size ?? ""
        quantity = it.quantity
        unit = it.unit
        minQuantity = it.minQuantity
        location = it.location ?? ""
        upc = it.upc ?? ""
        sku = it.sku ?? ""
        priceText = it.price.map { String(format: "%.2f", $0) } ?? ""
        photo = it.photo
        imageURL = it.imageURL
        productURLText = it.productURL ?? ""
        specs = it.specs
        notes = it.notes ?? ""
        onList = it.onList
    }

    func write(to it: Item) {
        it.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        it.brand = brand.nilIfBlank
        it.category = category
        it.lureType = lureType.nilIfBlank
        it.color = color.nilIfBlank
        it.size = size.nilIfBlank
        it.quantity = max(0, quantity)
        it.unit = unit
        it.minQuantity = max(0, minQuantity)
        it.location = location.nilIfBlank
        it.upc = UPC.normalize(upc)
        it.sku = sku.nilIfBlank
        it.price = Double(priceText.filter { $0.isASCIIDigit || $0 == "." }).flatMap { $0 > 0 ? $0 : nil }
        if it.photo != photo { it.photo = photo }
        it.imageURL = photo == nil ? imageURL : nil
        it.productURL = productURL
        it.specs = specs.compactMapValues(\.nilIfBlank)
        it.notes = notes.nilIfBlank
        it.onList = onList
        it.updatedAt = .now
    }
}
