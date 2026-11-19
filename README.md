# AULA Hub for macOS

A native Swift hub for the **AULA F75**: lighting effects and palettes, per-key RGB with themes, live animations,
key remapping with Windows and Mac tables, device settings, and backup/restore — as a SwiftUI Mac app and a CLI.

| Connection | USB id | What works |
|---|---|---|
| **USB cable** | `258a:010c` | everything: read and write |
| **2.4G dongle** | `3554:fa09` | read, back up, live lighting |
| **Bluetooth** | `3554:fa07` | status only: effect, mode, side light, knob, sleep, battery |

Settings are **only ever written over the cable.** Over the radio, packets get lost and a radio write is known to
have left an F75 unable to type until its firmware was reflashed, so the app refuses them (see Safety).

## Build

Needs only the Command Line Tools (no Xcode).

```sh
./scripts/build-app.sh      # → dist/"AULA Hub.app" and dist/aula
swift run aula-selftest     # 180 checks against simulated keyboards (cable and radio)
swift run aula --demo info  # try the CLI without hardware
swift run AulaHub --demo    # try the app without hardware
```

Quit the official AULA software first, and allow the app (or your terminal for the CLI) under
**System Settings → Privacy & Security → Input Monitoring**.

`build-app.sh` signs with a local certificate named *AULA Hub Local Signing* when it exists, so the Input Monitoring
permission survives rebuilds (ad-hoc signatures change with every build).

## The app

| Page | |
|---|---|
| Keyboard | live preview of the current lighting, keyboard mode, brightness, effect, side light, knob |
| Lighting | 16 firmware effects, brightness/speed/color, editable 7-color palettes, animated preview |
| Per-Key RGB | click/drag painting, 23 gradient themes, applies as the Custom effect |
| Live Animations | rendered on the Mac, streamed at 20 fps over the cable (about 14 fps on the dongle) |
| Key Remap | base/Fn layer × Windows/Mac table, legends for every key, quick changes, backup before each write |
| Settings | mode, side light, knob, Windows/Command-key lock, sleep timer, firmware, battery |
| Backups | everything the hub can read, in `~/Library/Application Support/AulaHub/backups` |

It connects by itself when the cable is plugged in, notices when it is pulled out, and has menus and shortcuts
(`⌘1`–`⌘7` pages, `⌘R` refresh, `⇧⌘B` backup, `⌃⌘W/M/A` Windows/Mac/Android mode).

### Mac mode

The keyboard has three OS modes (same as `Fn+W`, `Fn+E`, `Fn+Q`) and two key tables, Windows and Mac. Switch mode from
the toolbar, the Keyboard page, Settings or the **Keyboard ▸ Mode** menu (or `aula mode mac`). In Mac mode:

* keycaps in the app show Mac symbols — ⌘ ⌥ ⌃ ⇧ ⌫ ⏎ ⇥ — (Settings ▸ legends can force Windows or Mac);
* the Key Remap page opens on the Mac table;
* *Quick changes* has **Mac modifier order**, which swaps Alt and Win so the bottom row reads Ctrl ⌥ ⌘.

The Win key sends ⌘ Command and Alt sends ⌥ Option on macOS regardless of the mode.

## CLI

`aula help`. Examples:

```sh
aula info
aula mode mac
aula theme synthwave
aula remap capslock lctrl
aula --via dongle keymap          # read-only over 2.4G
aula --via dongle live rainbow-wave 10
aula backup
```

## Safety

* Reads and writes use the same framing as the official app (see `docs/protocol.md`).
* Every write is **read back and compared byte for byte**; a mismatch is reported.
* LED-block writes may only change bytes whose meaning is known; "sleep: never" is refused.
* Commands `0x88 0x8b 0x8e 0x91 0x11` over the cable (firmware code / factory reset) are never sent.
* Over the dongle and Bluetooth only reads and live frames are sent. The radio code has a whitelist of read commands and
  refuses every other write; a waiting period after the last key press avoids the keyboard dropping a key release.
* Take a backup before experimenting; the app also makes one before every keymap write.

## Credits and layout

See `NOTICE`. Source layout: `Sources/AulaKit` (protocol, models, legends), `Sources/aula` (CLI),
`Sources/AulaHub` (app), `Sources/AulaSelfTest` (tests), `scripts/` (build, icon), `Resources/` (app icon).
`AulaHub --demo --snapshot <dir>` renders the pages to PNG files for checking the interface from the command line.
