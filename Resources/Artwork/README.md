# Application icon

`AppIcon.png` is the generated square master artwork with transparency. The built-in image-generation tool produced it; the original generated copy remains in Codex's generated-images folder. This project-local copy is the build input.

`scripts/build-icon.sh` uses macOS `sips` to create the ten standard 1×/2× representations and `iconutil` to package them into an `.icns`. `scripts/build-app.sh` places that icon in the app bundle before signing it. `Resources/Info.plist` references `AppIcon.icns`, so Finder and the Dock can use it.

The icon is retained for the caption-only app. The original prompt records historical provenance; translation is no longer provided.

Generation prompt (built-in tool, transparent background):

> Use case: logo-brand. Asset type: production macOS app icon for ImmersionCaption, a native local subtitle translator for English learning. Create one polished square 1024 by 1024 icon. Center a rounded-square teal app tile with a subtle luminous teal-to-deep-blue gradient, gentle native macOS depth, and a crisp ivory caption/speech bubble containing two short dark teal subtitle strokes. Suggest listening and translation through the caption motif itself. Strong simple silhouette, generous spacing, restrained soft highlights, legible at 16–32 px. The tile occupies about 88% of the canvas with transparent space outside its rounded corners. No words, letters, flags, microphone, headphones, extra objects, watermark, or surrounding mockup. Genuine transparent background.

The actual generated master is 1254×1254 pixels; native packaging normalizes it to the required icon sizes while preserving alpha. A copy of the old app may keep its cached icon until quit and reopened; no Dock/cache reset is performed by the build scripts.
