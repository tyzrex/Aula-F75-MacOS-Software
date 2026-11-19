# Wired protocol (AULA F75, 258a:010c)

HID collection usage page `0xFF00`, usage 1, **feature report id 6, 520 bytes**.

```
[0]=06  [1]=cmd  [2]=sub  [3]=00  [4]=01  [5]=00  [6..7]=length (LE)  [8...]=data
```

Read: set-feature the request, wait ~20 ms, get-feature; the reply echoes the header then the data.
Writes are unacknowledged; wait ~0.4 s and read back.

| Read | Write | Data |
|---|---|---|
| 0x84 | 0x04 | LED block, 128 bytes, `5a a5` at 126 |
| 0x8a | 0x0a | palette page 512 bytes (490 palette + `5a a5` at 506); the LED block is re-sent afterwards |
| 0x86 | 0x06 | per-key colors, 378 bytes planar R[126] G[126] B[126] |
| 0x83 | 0x03 | keymap, sub = `layer \| system<<2`, 126 × `[type, mods, key2, key1]` |
| 0x82 | – | sub 1: 6-byte uuid, 2-byte version |
| 0x87 | – | battery: level, (charging<<4 \| full) |
| – | 0x08 | live frame: header `06 08 00 00 01 00 7a 01`, then R G B per matrix index |

**Keymap write (from the official Aula Hub 1.1.22):** header `03 sub 00 01 00 f8 01` (declares 504 bytes) followed by
512 bytes: the 504 key bytes, six zeros, `5a a5`. Reads ask for 504 bytes.

LED block offsets: `[10]` effect, `[15]` Win lock, `[18]` side light, `[24]` sleep (×30 s), `[26]` knob, `[27]` OS mode,
effect slots from `[58]` as `[brightness 0-9, speed<<4 | color]`.
Effects: 1 static, 2 breathing, 3 spectrum, 4 ripple-row, 5 raindrops, 6 wave, 7 ripple, 8 twinkle, 10 snake,
11 stream, 12 reactive, 13 center-wave, 15 rainbow-wheel, 16 waterfall, 17 center-flash, 32 custom.
