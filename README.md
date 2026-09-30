# ScreenTouch Mapper

A macOS menu bar app that pins a **mouse-mode touchscreen** to its own display.

## The problem

Many cheap USB touchscreens (for example the Verbatim PMT-15 portable monitor)
run their touch controller in *mouse mode*: every touch arrives as an absolute
mouse position. macOS has no touchscreen support, so it moves the pointer on the
display that has focus. With a second display, your touch lands on the wrong
screen.

ScreenTouch Mapper takes exclusive access to that mouse interface and sends each
touch to the display you choose.

## Does my screen need this?

Your screen probably runs in mouse mode when both are true:

- A touch moves the pointer, but on the display that has focus.
- `hidutil list` shows an entry with `UsagePage 1` and `Usage 2` (mouse) for
  the touchscreen, next to its digitizer entry (`UsagePage 13`).

After installation, open the menu of the app. Your touchscreen must appear under
**Touchscreens**. Only devices that report an absolute position appear there.
Trackpads and normal mice do not.

Screens that send real multi-touch data are not mouse-mode screens. For those,
use [Touch Up](https://github.com/shueber/Touch-Up).

An iPad in Sidecar is not a touchscreen for macOS: finger taps do not click.
ScreenTouch Mapper cannot change that, and the iPad does not appear in its menu.

## Install

1. Download `ScreenTouchMapper-<version>.zip` from the
   [releases page](https://github.com/k-ivanov/screentouch-mapper/releases) and unzip it.
2. Move **ScreenTouch Mapper.app** to **Applications**. Keep only this one copy.
3. The app is not notarized, so macOS blocks the first start:
   - **macOS 15 or later:** Open the app once and close the warning. Then go to
     **System Settings → Privacy & Security**, scroll down to the message about
     ScreenTouch Mapper, click **Open Anyway**, and confirm.
   - **macOS 13 or 14:** Right-click the app, select **Open**, then click
     **Open** again.
4. The app asks for two permissions and adds itself to both lists in
   **System Settings → Privacy & Security**. Turn on its switch in:
   - **Input Monitoring**: to take exclusive access to the touchscreen.
   - **Accessibility**: to send clicks.
5. Click the hand icon in the menu bar, open your touchscreen and select its display.
6. Optional: turn on **Start at Login** in the same menu.

## Use

| Touch | Result |
|---|---|
| Tap | Click |
| Two quick taps | Double-click |
| Touch and move | Drag |

If the touches are mirrored, turn on **Flip Horizontally** or **Flip Vertically**
in the device menu.

## How it works

1. The app lists the HID interfaces that report an absolute X/Y position and a
   primary button.
2. When you pair one with a display, the app opens that interface exclusively,
   so macOS no longer receives its events.
3. It scales each position from the device's logical range onto the display and
   posts the mouse events there.
4. When the display disconnects, or you quit the app, it releases the device,
   and macOS handles it as before.

Pairings are saved in
`~/Library/Application Support/ScreenTouch Mapper/pairings.json`.

## Troubleshooting

**The menu still shows "⚠ Accessibility needed" or "⚠ Input Monitoring needed",
but the switches are on.**
The app is ad-hoc signed. After an update, or when two copies of the app exist,
macOS can keep an old entry that no longer matches. Reset both entries and let
the app add itself again:

```sh
tccutil reset Accessibility com.kivanov.ScreenTouchMapper
tccutil reset ListenEvent com.kivanov.ScreenTouchMapper
```

Then delete every other copy of the app, open the copy in **Applications**, and
turn on the two new entries. Do not add the app with **+**.

**My touchscreen is not in the menu.**
- Check that the touch cable is connected. Many portable screens send touch only
  over USB-C, not over HDMI.
- Grant Input Monitoring. Without it, the app cannot read the devices.
- Your screen may not be a mouse-mode screen. See
  [Does my screen need this?](#does-my-screen-need-this)

**The device shows "⚠ Could not take exclusive access".**
Another app holds the device, for example another touch driver. Quit that app,
then open the menu again.

**The touches land at the wrong position.**
Use **Flip Horizontally** or **Flip Vertically**. The app does not support other
calibration.

**List what the app sees.**
From a terminal that has Input Monitoring, run:

```sh
"/Applications/ScreenTouch Mapper.app/Contents/MacOS/ScreenTouchMapper" --list
```

It prints each absolute-pointer device with its vendor and product ID, location,
serial number and axis ranges, and each display with its bounds.

## Limits

- Single touch only. Scroll and pinch gestures are not supported, because
  mouse-mode controllers report one point.
- The double-click time is fixed at 0.5 seconds. It does not follow the macOS
  setting.
- The app never takes a device by itself. Drawing tablets also report absolute
  positions. The menu marks them with "(tablet?)".

## Build from source

Requires Xcode 15 or later and macOS 13 or later.

```sh
make test   # run the unit tests
make app    # build "build/ScreenTouch Mapper.app" (universal, ad-hoc signed)
make zip    # build "build/ScreenTouchMapper-<version>.zip"
make icon   # redraw Resources/Icon/AppIcon.icns from make-icon.swift
```

Each ad-hoc build has a new signature. After you install a new build, reset the
permissions as described in [Troubleshooting](#troubleshooting).

The design and the implementation plan are in [`docs/`](docs/superpowers).
Changes per version are in [CHANGELOG.md](CHANGELOG.md).

## Licence

MIT. See [LICENSE](LICENSE).
