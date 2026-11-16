# App icon

Chosen 2026-11-14: **A3, "VFD meters"**: three segmented LED meters (8 segments, levels 4 / 7 / 5)
in VFD green on a near-black, green-tinted tile. One colour on purpose: the icon should be recognised
without thinking, and the shape carries that; the App Store screenshots show off the app's colours.

| File | What it is |
|---|---|
| `A3-vfd.svg` | The concept sketch Peter picked |
| `layers/1-background.svg` | Full-bleed background gradient, `#10201A` → `#040806` (top to bottom) |
| `layers/2-unlit.svg` | The unlit segments, solid `#12331C` |
| `layers/3-lit.svg` | The lit segments, solid `#3DFF70` |
| `preview.svg`, `preview.png` | The layers composited with a painted glow, for checking only |

The layers are flat on a 1024 × 1024 canvas with no rounded corners: Icon Composer applies the
macOS shape and the Liquid Glass effects itself. Unlit segments are a solid dark green rather than
a transparent bright one, so the tinted and clear styles (which work from brightness) keep the
lit/unlit contrast.

## Building it in Icon Composer

1. Open Icon Composer (Xcode ▸ Open Developer Tool ▸ Icon Composer) and start a new macOS icon.
2. Background: set the icon's fill to a gradient `#10201A` → `#040806`, or drag in
   `1-background.svg` as the bottom layer.
3. Drag in `2-unlit.svg`, then `3-lit.svg`, each as its own group, lit on top.
4. Lit group: Liquid Glass on, **chromatic shadow** (it gives the green glow the preview fakes with
   a blur), specular on. Unlit group: little or no glass, no shadow.
5. Check Default, Dark, Clear and Tinted in the preview; the lit segments should stay clearly
   brighter than the unlit ones in every style.
6. Save as `ActivityInspector.icon` and add it to the app target in Xcode (set the target's App Icon to
   it).

## Dev icon (2026-11-16)

Debug builds are a separate app (`ca.peter-jones.ActivityInspector.dev`, "Activity Inspector Dev") and
use `ActivityInspector/ActivityInspectorDev.icon`, so they can be told apart from the release in the
Dock and in Login Items. It is the release icon unchanged plus one more group on top, **Ribbon**:
`layers/4-ribbon.svg`, an amber (`#FFBF33`) band at 45° across the top-right corner with "DEV" in
near-black (`#0A0A0A`) Helvetica Neue Bold capitals. The letters are outlines, not SVG text, so Icon
Composer can't substitute a font. The group has glass off and no shadow, so the band stays flat and
crisp over the glassy meters. At 32 px the word is unreadable and only the amber corner shows;
Peter chose that over an all-amber icon.

To change the release icon, change both `.icon` bundles: the Dev one is a copy, not a reference.
