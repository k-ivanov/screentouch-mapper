# ScreenTouch Mapper — Design

Date: 2026-09-30
Status: Implemented in v1.0.0 (see section 11 for changes made during implementation)

## 1. Problem

Many cheap USB touchscreens (for example the Verbatim PMT-15, USB `0x27c0:0x0859`)
run their touch controller in **mouse mode**. They report every touch through a
Generic Desktop *Mouse* interface with **absolute** X/Y, not through the HID
digitizer interface. Their firmware ignores the HID *Device Mode* feature
report that Windows uses to switch them to multi-touch.

macOS has no touchscreen support. It treats such a device as an absolute mouse
and maps it to the display that currently has focus. With a second display,
a touch on the touchscreen lands on the wrong screen.

Touch Up (RWTH) does not help: it reads only the digitizer interface, which
these controllers leave silent.

## 2. Goal and audience

A small macOS menu bar app that pins any mouse-mode touchscreen to its own
display. Audience: owners of any touchscreen that reports as an absolute
mouse, not only the Verbatim.

**Success:** a user with a different mouse-mode touchscreen downloads the app,
selects the device and the display in the menu, and touches land on the
correct display, while another display has focus. No code change is needed.

## 3. Scope

In scope:

- macOS 13 or later, Apple silicon and Intel.
- Single touch: move, tap (click), drag, double-tap.
- Several device-to-display pairings at the same time.
- Ad-hoc signed release zip. There is no Developer ID, so no notarization.

Out of scope:

- Multi-touch, scroll and pinch gestures. Mouse-mode controllers report one point.
- Devices that already send real digitizer data (Touch Up covers those).
- Calibration beyond axis flip.
- Automatic pairing.

## 4. Names

| Item | Value |
|---|---|
| Product name | ScreenTouch Mapper |
| App bundle | `ScreenTouch Mapper.app` |
| Bundle ID | `com.kivanov.ScreenTouchMapper` |
| Repository | `github.com/k-ivanov/screentouch-mapper` |
| Swift package | `ScreenTouchMapper` |
| Library target | `ScreenTouchCore` |
| App target | `ScreenTouchMapper` |
| Release asset | `ScreenTouchMapper-<version>.zip` |
| Licence | MIT (already in the repository) |

## 5. Project structure

Swift Package plus a Makefile. No Xcode project.

```
Package.swift
Makefile
Resources/Info.plist
Sources/ScreenTouchCore/      library, no UI
Sources/ScreenTouchMapper/    menu bar app
Tests/ScreenTouchCoreTests/
docs/superpowers/specs/
README.md
LICENSE
```

- `swift build` / `swift test` work from the terminal.
- `make app` assembles `build/ScreenTouch Mapper.app` from the release binary and
  `Resources/Info.plist`, then signs it ad-hoc (`codesign --sign -`).
- `make zip` produces `build/ScreenTouchMapper-<version>.zip` with `ditto -c -k --keepParent`.
- The version comes from `CFBundleShortVersionString` in `Resources/Info.plist`.

## 6. Components

### 6.1 `ScreenTouchCore`

- **`PointerDevice`** — value type describing one HID interface: vendor ID,
  product ID, product name, serial number (may be empty), USB location ID, the
  X, Y and Button 1 element cookies, and the logical min/max of X and Y. A flag
  `looksLikeTablet` is true when the interface also has Digitizer page pen or
  stylus usages. Only interfaces with **absolute** X and Y qualify.
- **`DeviceScanner`** — wraps `IOHIDManager`. Matches Generic Desktop Mouse and
  Pointer interfaces, keeps those with absolute X/Y, and reports connect and
  disconnect. `rescan()` retries devices whose elements were not readable yet (see section 11).
- **`DisplayInfo`** — value type: `CGDirectDisplayID`, localized name, vendor
  number, model number, serial number, and global bounds (`CGDisplayBounds`).
- **`CoordinateMapper`** — pure function:
  `(rawX, rawY, rangeX, rangeY, bounds, flipX, flipY) -> CGPoint`.
  Normalises each axis to 0…1, clamps it, flips it when asked, and scales it into
  `bounds` (global top-left coordinates, which may have negative origins).
  The result is always inside `bounds`: x ≤ `bounds.maxX - 1`, y ≤ `bounds.maxY - 1`.
- **`ClickStateMachine`** — pure logic. Input: `(isDown, point, time)`.
  Output: a list of `PointerEvent` values: `move`, `down(clickCount)`,
  `drag`, `up(clickCount)`. A down within the double-click interval and within
  a distance tolerance of the previous down increments `clickCount`; otherwise
  it resets to 1. An `up` without a `down` produces nothing.
- **`EventPoster`** — protocol with a `CGEvent` implementation. Posts to
  `.cghidEventTap` and sets `mouseEventClickState`. The only part that needs
  Accessibility.
- **`Pairing`** — `Codable`: device match key (vendor ID, product ID, serial
  number, location ID), display match key (vendor, model, serial number,
  display ID), `flipX`, `flipY`.
- **`PairingStore`** — loads and saves `[Pairing]` as JSON in
  `~/Library/Application Support/ScreenTouch Mapper/pairings.json`.
  Device match: vendor + product + serial when the serial is not empty,
  else vendor + product + location ID. Display match: vendor + model + serial,
  else display ID. A missing or damaged file gives an empty list and no crash.

### 6.2 `ScreenTouchMapper` (app)

- **`AppDelegate`** — runs as an accessory app (`LSUIElement`), owns the
  status item, the scanner, the store and the sessions.
- **`MenuController`** — builds the menu each time it opens:
  - Permission rows: "⚠ Accessibility needed" / "⚠ Input Monitoring needed",
    each opening the matching System Settings pane. Hidden when granted.
  - "Devices": one item per absolute-pointer device (name, marked "(tablet?)"
    when `looksLikeTablet`). Submenu: "Off", then each display; the current
    choice has a check mark. Also "Flip X" and "Flip Y" toggles. A device whose
    seize failed shows "⚠ Could not take exclusive access".
  - "Start at Login" toggle via `SMAppService.mainApp`.
  - "Quit".
- **`Session`** — one active pairing. Opens the device with
  `kIOHIDOptionsTypeSeizeDevice`, registers an input value callback, keeps the
  latest X, Y and button values, and on each report runs
  `CoordinateMapper` → `ClickStateMachine` → `EventPoster`.

Data flow:

```
HID value → Session → CoordinateMapper → ClickStateMachine → EventPoster
```

## 7. Behaviour and error handling

- **Permissions.** Checked at start and each time the menu opens
  (`AXIsProcessTrusted`, `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`).
  When both become granted, saved pairings start without a restart.
- **Seize failure.** The session does not post any events, and the menu shows
  the warning. This prevents a double pointer.
- **Device disconnect.** The session stops and releases the seize. On
  reconnect, the saved pairing is matched and the session starts again.
- **Target display missing.** The session pauses and releases the seize, so the
  device works as a plain mouse again. It resumes when the display returns.
- **No auto-pairing.** A device is only seized after the user selects a display
  for it.
- **Quit or crash.** macOS releases the seize with the process. The device
  returns to default macOS behaviour.

## 8. Testing

Unit tests with `swift test`, no hardware:

- `CoordinateMapper`: corners, centre, flipped axes, non-zero logical minimum,
  out-of-range values (clamped), display with a negative origin.
- `ClickStateMachine`: tap, drag, double-tap in time and near, second tap too
  late, second tap too far, `up` without `down`.
- `PairingStore`: save and load round trip, serial match, location-ID
  fallback, damaged JSON gives an empty list.

IOKit and CGEvent code sits behind thin adapters and is not unit tested.

Manual test with the Verbatim PMT-15 before the release:

1. Pair it with its display. Check tap, drag and double-tap while the built-in
   display has focus.
2. Unplug and replug it. The session must start again.
3. Quit the app. The device must return to default macOS behaviour.

## 9. Documentation

`README.md` covers: the problem, how to tell if a screen runs in mouse mode
(the pointer follows the focused screen, and `hidutil list` shows a Generic
Desktop Mouse interface for the device), installation, the first-launch
right-click → Open step for an unnotarized app, the two permissions, the
limits (single touch, no gestures), and how to build from source.

## 10. Publication

- Commits on `main` of `k-ivanov/screentouch-mapper`, pushed to GitHub, in the
  user's commit format (`NO-TICKET <Title>`).
- GitHub release `v1.0.0` with the zip. Created only after explicit
  confirmation from the user.
- After the new app is installed and tested: remove
  `/Applications/VerbatimTouch.app` and `~/Developer/VerbatimTouch`.

## 11. Changes made during implementation

These points were decided while the plan was carried out. The code follows them.

- **Rescan after the permission grant.** HID elements can only be read after the
  device is open, and opening a pointer needs Input Monitoring. Devices found
  before the grant had no elements and stayed invisible. `DeviceScanner.rescan()`
  opens them again, and `SessionManager.reconcile()` calls it first.
- **Queue creation can fail.** `IOHIDQueueCreate` returns an optional in Swift.
  On `nil`, the session closes the device and reports
  `seizeFailed(kIOReturnNoMemory)`, so no half-open session remains.
- **Removal by reference.** An unplugged device's registry ID may no longer be
  readable, which left a stale entry and a duplicate menu item after a replug.
  The scanner now removes a device by its `IOHIDDevice` reference.
- **`--list` needs Input Monitoring for the terminal.** macOS grants the
  permission to the terminal app, not to the binary. The README uses the app
  menu and `hidutil list` as the main check.
- **Permission entries for ad-hoc builds.** Toggles can look on but not apply
  after a rebuild or with two app copies. The README documents the `tccutil`
  reset.

Known limits deferred from the final review:

- `rescan()` re-opens non-absolute pointers on each reconcile (no visible effect).
- The double-click interval is fixed at 0.5 s instead of following
  `NSEvent.doubleClickInterval`.
- A revoked permission stops the sessions only at the next reconcile.
