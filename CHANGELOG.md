# Changelog

## 1.10.0

- New scene, **Neon Coast**: hundred-dollar notes flutter down over a city sunset. Each note is built from hinged strips, so it is really folded in depth (creased, halved, curled or rippled), flexes as it falls and flips in three dimensions at different distances. Notes pile up on windows and the ground and scatter when the pointer brushes past.
- Driftwood runs in the background. It stays in the menu bar, shows in the Dock only while the gallery is open, and keeps the weather going with no windows open.
- On first launch Driftwood asks what it may do, and works without whatever you decline. **Open at Login** starts it with your scene when you log in. **Show on Lock Screen** puts the scene's picture on the lock screen by making it the system desktop picture, and restores your own picture afterwards.
- The menu bar item is now a native status item that responds on the press and opens its controls directly beneath it, and opening the app again always brings the gallery back.

## 1.9.0

- Weather now follows gravity, air drag and shared gusts of wind. Flakes fall at a terminal speed set by their size, leaves and petals rock as they fall, and sparks and splashes fly in arcs.
- Motion plays at the display's own refresh rate instead of 30 frames per second.
- CPU use while weather is showing dropped from about 8% of a core to about 0.5% at default settings on an Apple M4 with two displays (1 to 3% with both sliders at maximum), and memory from about 97 MB to 32 MB.
- Snow, leaves and petals ride along with a window that is moved steadily. A jerk shakes them loose with the window's own speed, so shaking a window throws snow off to both sides. Resizing drops only the strip that lost its footing.
- **Plough** (was **Plough Snow**) drives a plough across the screen that clears the ground and snowmen as it passes instead of everything vanishing at once.
- A flake now comes to rest where it lands and melts into the drift, which rises at that spot, so the snow you watch fall is the snow that builds up. Snow dropped from a resized window leaves a mound where it lands.
- While you drag a window its position is taken from the pointer on every frame, so the snow stays on it without lagging behind.
- Snowballs stack when dropped anywhere roughly over another ball, fall in real time and give a little as they land.
- Coming back to the desktop starts from nothing: an empty sky, bare ledges and bare ground.
- Drifts take their outline from where the snow happened to land: flakes pack down unevenly and every drift has its own lie, so the same ledge never builds up the same way twice.
- Move the pointer along a ledge or the ground to brush settled snow off it.
- Let go of a rolled snowball while moving fast to throw it. It flies in an arc and bursts where it lands.
- Closing, minimising and hiding windows are noticed within a fraction of a second, so snow no longer hangs where a window used to be.
- Every change of Space clears the weather at once and starts again from nothing after about three seconds.
- Ground snow settles into hilly drifts. Three stacked snowballs make a snowman with a hat, face, scarf, buttons and arms.
- The weather sits just beneath the Dock instead of guessing the Dock's outline, so the drifts line up on every Dock size. Snow no longer piles on the Dock itself.
- The weather no longer shows over a full-screen app while switching Spaces. Back on the desktop it waits about three seconds and then arrives from the top.
- **Change Wallpaper…** puts your own picture behind any scene, with the best size shown in the gallery. The last scene comes back when Driftwood reopens.
- Leaves and petals are drawn as leaves and petals. Meteors have a bright head and a fading tail, and raindrops leave a ring where they land. Leaves in the air are pushed by a passing pointer as well as the ones lying still.
- **Fall speed** now runs weather time faster or slower. Its default is natural speed.
- Driftwood has an app icon.
- Video wallpapers were removed.
- `build.sh` works with the Command Line Tools alone on the macOS 27 SDK.

## 1.8.0

First public release.

- Six illustrated scenes with animated weather and support for local MP4 and MOV wallpapers.
- Snow builds where it lands and can drop from moved windows onto exposed windows below.
- The menu bar includes density, fall speed, and a plough that clears settled snow and snowmen.
- The weather pauses on sleeping or full-screen-covered displays. Battery and Low Power Mode reduce particle density.
