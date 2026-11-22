# App icon sources

Vector sources for the app icon: barcode bars whose last bar curls into a fishing hook. `AppIcon.svg` is the default,
`AppIcon-dark.svg` is the iOS dark-mode version (blue mark on near-black), and `AppIcon-tinted.svg` is the grayscale artwork iOS
recolors for tinted home screens (its background is transparent on purpose).

To regenerate the PNGs in `TackleTracker/Assets.xcassets/AppIcon.appiconset` after editing (macOS):

```bash
qlmanage -t -s 1024 -o /tmp AppIcon.svg
```

The default and dark PNGs must have no transparency: convert through JPEG to drop the alpha channel,
for example `sips -s format jpeg /tmp/AppIcon.svg.png --out /tmp/a.jpg && sips -s format png /tmp/a.jpg --out AppIcon.png`.
