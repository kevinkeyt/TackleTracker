# TackleTracker

An iPhone app for keeping track of your soft plastics, hard baits, terminal tackle, line, rods and reels in the
tackle room. **All of your data stays on your phone.** There's no account and no server to keep running.

- **Scan a barcode** to see if you already own it (and how many), or add it if you don't. Works in the store too, so you don't buy what you already have.
- **Scan modes**: *Add +1* counts packages as you shelve them; *Take out −1* removes one per scan when you load the boat or use something up. Each scan can be undone.
- **Fill in from a product link**: paste the link to the product on any store's website. Whatever the page lists (name, brand, photo, price, SKU, UPC, and the colors or sizes it comes in) is filled in, and the link is saved for reordering. Photos are saved on the phone.
- **Reorder list**: set a "reorder at" level per item. Anything at or below it (or added to the list by hand) shows up with **Shop**, which opens the saved product link or searches the web.
- **Shopping list**: from the Reorder tab, pick what to buy and how many, then share it to Notes for a trip to your local tackle store.
- **Works offline.** Only filling in from a link, barcode lookup for new items, and Shop need a connection.
- **Backups** to Files / iCloud Drive (photos included) and spreadsheet (CSV) export from the **More** tab.

## Installing it on your iPhone

You need a Mac with Xcode (26 or later) and an iPhone on iOS 18 or later.

1. Open `ios/TackleTracker.xcodeproj` in Xcode.
2. Select the **TackleTracker** target → **Signing & Capabilities**, and pick your Apple ID under **Team**. If Xcode
   says the bundle identifier is taken, change `com.tackletracker.app` to something of your own, such as `com.yourname.tackletracker`.
3. Plug in your iPhone (or pair it over Wi-Fi), choose it as the run destination, and press **Run** (⌘R).
4. The first time, on the iPhone go to **Settings → General → VPN & Device Management**, and trust your developer certificate.

With a free Apple ID the app stops opening after 7 days; run it from Xcode again to renew it (your data is kept).
With the paid Apple Developer Program ($99/year) installs last a year, and you can share it through TestFlight.

### Moving over from the old web app

The web version kept its data in Safari, which the app can't read. In the web app, use **More → Back up now** and
save the file to Files. Then in the iOS app, use **More → Restore from a backup…** and pick that file. Photos come along.

## Backups

Data lives only on the phone, so deleting the app deletes your tackle list. Every couple of weeks, use
**More → Back up now** and choose **Save to Files** (iCloud Drive). The app reminds you if it's been a while.

The app is set up so iCloud sync can be turned on later (it needs the paid developer program): add the iCloud
capability with CloudKit in Xcode and change `cloudKitDatabase: .none` to `.automatic` in
[`TackleTrackerApp.swift`](ios/TackleTracker/TackleTrackerApp.swift).

## Barcode lookup for new items

Scanning always finds what you already own. For packages you haven't added yet, the app fills in the name and brand
through a small Cloudflare Worker relay ([`worker/`](worker/README.md)) to the free UPCitemdb lookup (about 100
lookups a day). Its address is built in and can be changed or cleared under **More → Barcode lookup**.

## Developing

Open `ios/TackleTracker.xcodeproj` and run on a simulator or phone. The project uses
[SwiftSoup](https://github.com/scinfu/SwiftSoup) (fetched by Xcode) to read product pages. Product details come from
the structured data most stores publish for search engines and link previews: schema.org JSON-LD, schema.org microdata,
then Open Graph tags.

Run the tests with ⌘U in Xcode, or:

```bash
xcodebuild test -project ios/TackleTracker.xcodeproj -scheme TackleTracker -destination 'platform=iOS Simulator,name=iPhone 17'
```

Live camera scanning needs a real iPhone; in the Simulator, use **Snap photo** (which picks from the photo library)
or type the UPC. In Debug builds, launching with the `-seedSampleData` argument replaces the list with a few sample
items for trying out screens.

## Layout

- `ios/TackleTracker/Model`: the `Item` SwiftData model, categories, UPC handling
- `ios/TackleTracker/Services`: product page import, barcode lookup, photos, shopping list, backup/restore/CSV
- `ios/TackleTracker/Views`: the Tackle, Scan, Reorder and More tabs and the item screens
- `ios/TackleTrackerTests`: unit tests
- `worker/`: the barcode lookup relay (Cloudflare Worker)
