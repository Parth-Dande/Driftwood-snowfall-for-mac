# Driftwood

Driftwood puts weather on your Mac desktop. Pick one of six illustrated scenes and snow, rain, petals, leaves, fireflies or meteors fall over your wallpaper, land on your windows and react when you move them. It runs offline and uses about half a percent of one CPU core.

## Install

Download **Driftwood-macOS.zip** from [GitHub Releases](https://github.com/Parth-Dande/driftwood/releases/latest), unzip it, and open **Driftwood.app**. Driftwood needs macOS 14 or later and runs on Apple silicon and Intel. The release is ad hoc signed; if macOS blocks it, build it yourself with the instructions below. Building from source also gives you the newest version when a release has not been published yet.

## Scenes

| Scene | Weather | What it does |
| --- | --- | --- |
| Snow Lantern Inn | Snow | Piles up on window tops and the ground, and can be rolled into snowballs |
| The Rainy Bookshop | Rain | Splashes on window tops and the ground, with lightning now and then |
| Blossom Creek | Petals | Drift down and rest on your windows for a while |
| Cider Mill | Leaves | Pile up and scatter when the pointer brushes past |
| Lantern Marsh | Fireflies | Wander, and gather round a pointer that holds still |
| Campfire Lake | Meteors | Streak across and burst into sparks on your windows |

## Using Driftwood

- Choose a scene in the gallery and select **Apply to All Displays**. The scene comes back the next time Driftwood opens.
- **Weather density** sets how much falls; at the high end snowflakes also get larger. **Fall speed** runs weather time faster or slower, and its default is natural speed. Both sliders are in the gallery and in the cloud-and-moon menu bar item, and both are saved.
- Turn **Motion** off to keep the picture and stop the weather.
- Close the gallery to leave the wallpaper running. The menu bar item reopens it, switches scenes and quits.
- **Clear**, or quitting Driftwood, shows your regular desktop picture again.

### Snow

- Snow builds up on window tops and settles into drifts along the bottom of the screen. Each drift takes its outline from where the snow happened to land, so it never builds the same way twice.
- Move a window steadily and its snow rides along. Shake it and the snow flies off to both sides. Stop it short on the way up and the snow is tossed into the air. Resize it and only the strip that lost its footing drops, onto another window if one is below.
- Run the pointer along a window's top edge or the ground to brush the snow off.
- Drag up from the bottom edge of the screen to roll a snowball. Let go over another ball to stack it; three make a snowman with a hat, face, scarf, buttons and arms. Let go while moving fast to throw it instead.
- **Plough** in the menu bar sends a plough across the screen. Snow on window ledges tips off, and the blade clears the drifts and snowmen as it passes.

### Your own wallpaper

Select **Change Wallpaper…** in the gallery to put your own picture behind the selected scene's weather, and **Use Original** to bring the bundled artwork back. A landscape JPEG, PNG or HEIC at least as large as your biggest display in pixels stays sharp; the gallery shows that size. Your picture is copied into `~/Library/Application Support/Driftwood/Wallpapers`.

## How it behaves

- The weather is a transparent overlay that sits just beneath the Dock and above your windows. Open windows hide the weather over their contents, and clicks pass straight through.
- Collisions use the window bounds macOS reports, so browser tabs that share a window share its top edge. Weather passes behind Stage Manager thumbnails.
- A sleeping display, or one covered by a full-screen window, pauses its weather. When the desktop comes back, or you switch Space, everything clears and starts again from nothing after about three seconds.
- On battery or in Low Power Mode Driftwood halves the density.
- Driftwood's desktop layer is separate from the system wallpaper and the lock screen.

## How it works

Every particle is a body falling under gravity against air drag, with its own terminal speed, carried by slow gusts that neighbouring particles share. Bigger flakes are heavier and fall faster, leaves and petals rock and slow at the ends of each swing, and sparks and splashes follow ballistic arcs.

Driftwood works out each particle's whole path once and hands it to the macOS compositor, which plays it back at the display's own refresh rate, including 120 Hz. Driftwood itself wakes about five times a second to launch new particles and look at your windows, and up to sixty times a second while you drag a window. On an Apple M4 with two displays that comes to about 0.5% of one CPU core at the default settings and 1 to 3% with both sliders at maximum.

## Build from source

With the Xcode Command Line Tools or Xcode installed, run these from the repository root:

```sh
./build.sh
open build/Driftwood.app
```

The build produces a universal binary and has no package dependencies. With only the Command Line Tools installed, `build.sh` picks an SDK whose SwiftUI does not need Xcode's macro plugin; set `DRIFTWOOD_SDK` to an SDK path to choose one yourself.

To start a scene straight away, pass its name: `open build/Driftwood.app --args -applyScene snow`. The names are `snow`, `rain`, `petals`, `leaves`, `fireflies` and `stars`.

## Project layout

```
Sources/
  App/         App entry point and the desktop state shared by the interface
  Interface/   Gallery window, menu bar item and scene previews
  Scenes/      The six scenes and the wallpaper store
  Desktop/     Wallpaper windows and display helpers
  Weather/     Overlay windows, window tracking, rendering, physics and sprites
  Snow/        Rolling, stacking and throwing snowballs
Resources/
  Info.plist   Bundle metadata
  AppIcon.icns App icon
  Artwork/     The six wallpapers and their references
build.sh       Builds the universal macOS app into build/
```

## Credits and license

KoiArt’s public wallpaper gallery and weather demo video inspired the themed wallpapers, all-displays action, and desktop weather interactions. Driftwood’s artwork, particles, interface, and name were made independently. The six bundled wallpapers were generated for Driftwood with ImageGen. See [Resources/Artwork/REFERENCES.md](Resources/Artwork/REFERENCES.md) for the visual references and prompts. The app includes no KoiArt artwork, videos, branding, or code.

Driftwood reuses the desktop window and display identification code from [WallFlow](https://github.com/ritulsingh/WallFlow/tree/b0946f519e9b8143e223ba3a9dceeca454f206a8), copyright 2026 ritulsingh, under the MIT license. The desktop window code was adapted for this app. See [LICENSE-WallFlow](LICENSE-WallFlow) for the full upstream notice. The original Driftwood portions are also available under MIT terms in [LICENSE](LICENSE).
