# AULA Hub for macOS

A native Swift hub for the **AULA F75** (USB `258a:010c`): lighting effects and palettes, per-key RGB with themes,
live animations, key remapping, device settings, and backup/restore — as a SwiftUI app and a CLI.

**Cable only.** The keyboard can be configured only over USB. The 2.4G dongle (`3554:fa09`) and Bluetooth are not used.

## Build

Needs only the Command Line Tools (no Xcode).

```sh
./scripts/build-app.sh      # → dist/"AULA Hub.app" and dist/aula
swift run aula-selftest     # 131 checks against a simulated keyboard
swift run aula --demo info  # try the CLI without hardware
```

Quit the official AULA software first, and allow the app (or your terminal for the CLI) under
**System Settings → Privacy & Security → Input Monitoring**.

## What it does

| Page | |
|---|---|
| Lighting | 16 firmware effects, brightness/speed/color, editable 7-color palettes, animated preview |
| Per-Key RGB | click/drag painting, 23 gradient themes, applies as the Custom effect |
| Live Animations | rendered on the Mac, streamed at 20 fps (nothing stored on the keyboard) |
| Key Remap | base/Fn layer × Windows/Mac table, automatic backup before each write, read-back check |
| Device | side light, knob mode, OS mode, Windows-key lock, sleep timer, firmware, battery |
| Backups | everything the hub can read, in `~/Library/Application Support/AulaHub/backups` |

CLI: `aula help`.

## Safety

* Reads and writes use the same framing as the official app (see `docs/protocol.md`).
* Every write is **read back and compared byte for byte**; a mismatch is reported.
* LED-block writes may only change bytes whose meaning is known; "sleep: never" is refused.
* Commands `0x88 0x8b 0x8e 0x91 0x11` (firmware code / factory reset) are never sent.
* Not tested on a real keyboard yet (none was attached while building): the protocol layer is verified against a
  simulated device and against the official app's source. Take a backup first and report anything odd.
