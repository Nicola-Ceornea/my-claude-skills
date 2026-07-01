---
name: nv3007-lcd-designer
description: Drive a physical NV3007 SPI LCD (EastRising ER-TFTM1.65-2, 142x428 RGB565 IPS) from a laptop over a Waveshare "USB TO UART/I2C/SPI/JTAG" bridge, to design/iterate UI visuals on the real screen without any dev board. The bridge is a WCH CH347T (enumerates as USB 1a86:55db "USB To UART+SPI+I2C" in Mode M1), NOT an FTDI chip — so the software is a self-contained pure-Python pyusb/libusb driver (bundled in scripts/), runs on macOS and Linux with no kernel module and no vendor DLL. Trigger this skill whenever the user wants to: show an image / PNG / mockup on the NV3007 or ER-TFTM1.65-2 panel, iterate on wallet/hardware UI on the physical screen, set up the CH347 / Waveshare USB-to-SPI bridge on a new Mac or Linux box, drive a 142x428 SPI TFT from a PC, debug "nothing shows on the LCD", or figure out the CH347 (1a86:55db) SPI+GPIO protocol. Covers brand-new-machine install (brew/apt + libusb + pyusb), the exact panel<->bridge wiring, a live design-iteration loop, and the CH347 vendor protocol.
---

# nv3007-lcd-designer — drive the NV3007 wallet LCD from a laptop

Push images to the **real** NV3007 panel over a USB bridge so a designer can
make the UI look good on the physical screen — **no MCU / dev board required**.
It's pure visual bring-up: convert a PNG → RGB565, stream it to the panel,
iterate. All the code is bundled in [`scripts/`](scripts/); it's a faithful port
of the production firmware's panel init, geometry, and orientation, so what shows
on the bench equals what the device renders.

Runs identically on **macOS** (a designer's MacBook) and **Linux**. Pure Python +
libusb (pyusb), no kernel module, no code-signing, no vendor DLL.

---

## The hardware you're driving

### The panel — EastRising ER-TFTM1.65-2 (controller NV3007)

| Property | Value |
|---|---|
| Size / type | 1.65″ IPS TFT, **142 × 428 px**, 65K/262K colors |
| Controller | **NV3007**, 4-wire 8-bit **SPI, mode 0** (CPOL=0, CPHA=0), MSB-first |
| Pixel format | **RGB565, big-endian** on the wire (high byte first) |
| Active area | 13.16 × 39.68 mm, 0.09 mm dot pitch |
| Logic / supply | **3.3 V** logic; VCC **3.0 / 3.3 / 3.5 V** (never exceed 3.5 V); ≤ 60 mA |
| Connector | 8-pin 0.1″ header, silkscreen order **`GND · VCC · SCK · MOS · RES · DC · CS · BLK`** |

Pin functions (from the datasheet):
- **SCK** = SPI clock. **MOS** = SPI data-in (MOSI; datasheet calls it SDA). *Write-only — there is no MISO/read-back.*
- **RES** = reset, **active-low**. This tool ties it high and uses the software SWRESET (`0x01`), so RES can just go to 3.3 V.
- **DC** = data/command select: **0 = command, 1 = data**. This is the one true GPIO the tool drives.
- **CS** = chip select, **active-low**.
- **BLK** = backlight **logic enable** (High = on) — a control pin into an onboard driver, *not* a raw LED. Tie to 3.3 V for always-on.

Orientation: the panel is physically **142 (W) × 428 (H) portrait**, but the wallet
UI is viewed **landscape (428 × 142)**. The tool rotates a landscape design onto
the panel (90° + horizontal flip, matching the firmware) and applies the
controller's **+12 X offset** automatically. So **design on a 428 × 142 canvas**.

### The bridge — Waveshare "USB TO UART/I2C/SPI/JTAG" = WCH **CH347T**

Despite the "USB-to-SPI" name it is **not FTDI** (so `pyftdi`/`libmpsse` do **not**
apply). It's a WCH **CH347T**. Confirm with `lsusb`:

```
Bus ... Device ...: ID 1a86:55db QinHeng Electronics USB To UART+SPI+I2C
```

`1a86:55db` = **CH347T Mode 1** (UART1 + SPI + I2C). SPI/I2C/GPIO ride a
**vendor-class USB interface (interface 2, bulk EP 0x06 OUT / 0x86 IN)** that no
OS driver claims — the driver talks to it directly over libusb. (The "UART1" also
present is a normal `/dev/ttyACM*` / `/dev/tty.usbmodem*` we ignore.)

> ⚠️ **The board has TWO switches, both latched at power-on — set them before
> plugging in USB:**
> - **Mode DIP → M1** (gives `55db` = UART1 + SPI + I2C).
> - **Level slide switch → 3.3 V** (sets I/O + VCC voltage).
>
> These are **independent**. M1 does *not* set the voltage. If the level switch is
> on **5 V**, the header VCC **and every signal line** become 5 V and **will
> destroy the 3.0–3.5 V panel**. Always meter **VCC → GND ≈ 3.3 V** before
> connecting the panel.

---

## Wiring

The panel's 8-pin header maps to the CH347 board as follows. Only 6 wires go to
the **SPI** block; **DC is the single wire on the UART block**; RES + BLK just
jumper to the 3.3 V rail.

| NV3007 pin | → CH347 board pin | Detail |
|---|---|---|
| **GND** | SPI block **GND** | common ground |
| **VCC** | SPI block **VCC** | must meter ≈3.3 V (level switch @ 3.3 V) |
| **SCK** | SPI block **SCK** (CLK) | idles low in mode 0 — a 0 V reading here is correct |
| **MOS** | SPI block **MOSI** | panel MOS = SDA (data-in); the CH347 silk may read **SDO** — don't wire to SDI/MISO |
| **RES** | **3.3 V** (VCC) | tie high; the tool resets in software (SWRESET `0x01`) — there is no hardware-reset code path |
| **DC** | UART block **CTS** | = **CH347 GPIO index 6**, driven as a GPIO output |
| **CS** | SPI block **CS0** | hardware chip-select (SCS0) |
| **BLK** | **3.3 V** (VCC) | backlight always on |

---

## Quick start (brand-new machine)

The driver is bundled in this skill's `scripts/` folder. Below, **`<skill>`** = the
directory this `SKILL.md` lives in — when installed the usual way that's
`~/.claude/skills/nv3007-lcd-designer`. Copy the scripts **and this SKILL.md** (for
an on-hand wiring reference) to a working directory, make a venv, and run.

### macOS (Apple Silicon or Intel)

A **brand-new Mac** ships neither Homebrew nor a usable `python3` — install those
first (skip any that already work):

```bash
# 1. Homebrew. On Apple Silicon the installer only writes the PATH line to
#    ~/.zprofile, so also load it into THIS shell:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"     # Intel Macs: eval "$(/usr/local/bin/brew shellenv)"

# 2. libusb + a clean Python. Homebrew's python avoids the /usr/bin/python3 CLT
#    stub that pops a GUI "install developer tools" dialog on a fresh Mac.
brew install libusb python
```

Then set up and run:

```bash
mkdir -p ~/nv3007
cp -r "<skill>/scripts/"* "<skill>/SKILL.md" ~/nv3007/ && cd ~/nv3007
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip && ./.venv/bin/pip install -r requirements.txt
# set the CH347: Mode DIP = M1, Level switch = 3.3V, then plug it into USB
./.venv/bin/python show.py test
```

No `sudo`, no kext, no code-signing: macOS claims only the CDC-UART interfaces;
the SPI vendor interface is free. numpy/Pillow install as prebuilt arm64 wheels
(no compiler needed). The driver already points pyusb at Homebrew's libusb
(`/opt/homebrew/lib` on Apple Silicon, `/usr/local/lib` on Intel), sidestepping
the common `NoBackendError`.

### Linux (Debian/Ubuntu)

```bash
sudo apt install -y libusb-1.0-0 python3-venv
mkdir -p ~/nv3007
cp -r "<skill>/scripts/"* "<skill>/SKILL.md" ~/nv3007/ && cd ~/nv3007
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip && ./.venv/bin/pip install -r requirements.txt

# grant non-root USB access (once): install the udev rule, then REPLUG the board
sudo cp 99-ch347.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger

# set the CH347 (Mode M1, Level 3.3V), replug, then:
./.venv/bin/python show.py test
```

The bundled `99-ch347.rules` grants every local user access (`MODE="0666"`), so no
group membership is needed. Without the rule the USB node is root-only — you can
instead prefix a single run with `sudo ./.venv/bin/python show.py test`. The udev
rule is the clean path (no sudo afterward) and is required for the `watch` loop.

---

## Usage

```bash
python show.py test                 # green/red/blue fills + an orientation 'F'
python show.py fill 00FF00          # solid RGB (RRGGBB)
python show.py image mock.png       # push a design (428x142 landscape assumed)
python show.py image portrait.png --orient native   # treat as 142x428 portrait
python show.py watch mock.png       # LIVE: re-push whenever the file changes
python show.py watch designs/       # watch a folder, show the newest image
```

Flags go **after** the subcommand (`show.py image x.png --orient native`). Common
to test/fill/image/watch: `--freq 15e6` (SPI clock; 30e6 for snappier repaints),
`--orient wallet|native`, `--fit contain|cover|stretch`, `--flip-x/--no-flip-x`,
`--flip-y`, `--dc-gpio N`, `--cs-gpio N`, `--no-init` (skip re-init). Watch-only:
`--interval SECONDS` (poll period, default 0.3).

### The designer loop

Design on a **428 × 142** landscape canvas (Figma/Sketch/Photoshop), export a PNG,
and leave `python show.py watch designs/mock.png` running. The watch loop polls
the file every ~0.3 s and re-pushes the moment it changes. Iterate until it looks
right.

---

## First-bring-up checklist

The panel electrical spec and the CH347 protocol are verified from datasheets and
WCH's own driver, and the pipeline has been validated end-to-end on real
hardware. On a **new panel/board**, still walk these once:

1. **Switches:** Mode **M1**, Level **3.3 V** — set *before* USB. Meter
   **VCC → GND ≈ 3.3 V** and **CS0 idle ≈ 3.3 V** (not 5 V). SCK idles low in
   mode 0 — don't use it to check voltage.
2. **`python show.py test`:** expect **green → red → blue** fills (confirms SPI +
   init + color order), then a red **F** + green arrow pointing right.
   - Mirrored/rotated F → add `--flip-x/--no-flip-x/--flip-y` (or `--orient`)
     until it reads right; note the combo. An "F" reveals mirrors a color bar hides.
3. **(Optional) logic analyzer:** confirm the actual SCK frequency (WCH doesn't
   publish the clock base, so `--freq` is nominal) and that **DC = GPIO6** toggles
   low(command)/high(data). If DC doesn't move, try another `--dc-gpio`.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `NoBackendError` | libusb missing. macOS: `brew install libusb`. Linux: `apt install libusb-1.0-0`. Apple Silicon: ensure `/opt/homebrew/lib/libusb-1.0.dylib` exists (or `export DYLD_LIBRARY_PATH=/opt/homebrew/lib`). |
| `... not found (1a86:55db)` | Mode DIP not at M1, or set after power-on. Set M1, replug. Check `lsusb \| grep 1a86` (Linux) / `system_profiler SPUSBDataType \| grep -i 1a86` (macOS). |
| `USBError: Access denied` (Linux) | udev rule not installed. `sudo cp 99-ch347.rules /etc/udev/rules.d/ && sudo udevadm control --reload-rules && sudo udevadm trigger`, replug — or run once with `sudo`. |
| `USBError: Resource busy` | A prior/crashed run still holds interface 2 — unplug/replug the CH347 (works on macOS + Linux). Linux only: if WCH's out-of-tree `ch347` kernel module is loaded, `sudo modprobe -r ch347`. |
| `ModuleNotFoundError: No module named 'PIL'/'usb'` | Deps not in the active env. `./.venv/bin/pip install -r requirements.txt` and run with `./.venv/bin/python`. |
| Fills don't show, no error | Wiring (esp. MOS↔MOSI, DC pin) or the level switch isn't 3.3 V. Re-check wiring + switches. |
| Init errors / garbage screen | If the hardware CS doesn't hold across a command+params window, multi-param init commands corrupt. Fallback: wire panel **CS → UART RTS** and run with `--cs-gpio 7` (drives CS from a GPIO — fully deterministic). |
| Image sideways/mirrored | Orientation flags — see checklist step 2. |
| Tearing during a change | Cosmetic: a full-frame repaint races the panel scan-out. Static frames are clean. |

---

## How it works (for debugging / extending)

**Files** (`scripts/`):

| File | Role |
|---|---|
| `nv3007.py` | Panel driver: the full NV3007 init sequence, geometry (X_OFFSET=12), `set_window`, `blit_full`, and a bridge-agnostic `Transport` interface. **Nothing bridge-specific.** |
| `image_convert.py` | PNG → native 142×428 RGB565 (big-endian) + the landscape↔native orientation transform. |
| `ch347.py` | The CH347 SPI+GPIO transport over pyusb (the one bridge-specific file). |
| `show.py` | CLI: `test` / `fill` / `image` / `watch`. |
| `requirements.txt` | `pyusb`, `Pillow`, `numpy`. |
| `99-ch347.rules` | Linux udev rule for non-root access to `1a86:55db`. |

**To support a different USB-SPI bridge**, implement one `nv3007.Transport`
(`command(cmd, params)` + `pixels(data)`) — nothing else changes.

**CH347 vendor protocol** (in `ch347.py`, verified byte-for-byte against WCH's GPL
driver `WCHSoftGroup/ch34x_mphsi_master_linux`): claim USB interface 2, then every
command is `[opcode, len_lo, len_hi, payload]` on bulk EP `0x06` OUT, with a reply
drained on EP `0x86` IN:
- `0xC0` SPI init — 26-byte config; build it by reading the live config with
  `0xCA` INFO_RD and patching cpol@6 / cpha@8 / baudrate_scale@12 (= iclock×8) /
  firstbit@14. Reply 4 B, status at `[3]`.
- `0xC1` CS control — 13-B packet; CS byte **`0x80` = assert, `0xC0` = deassert**
  (write-only, no reply). Assert once, stream, deassert → CS holds across chunks.
- `0xC4` block write — write-only SPI; **≤ 507 data bytes per packet**; 4-B ack,
  `[3] == 0x00`. A full 121,552-byte frame ≈ 240 packets.
- `0xCC` GPIO — 8 config bytes (GPIO0..7); **`0xF8` = output-high, `0xF0` =
  output-low**, `0x00` = leave alone. 11 B out / 11 B in.

The NV3007 init sequence (`INIT_SEQ` in `nv3007.py`) is the production dgen1
sequence: vendor unlock (`0xFF/0xA5`) → gamma/GOA/timing tuning → relock
(`0xFF/0x00`) → **COLMOD `0x3A=0x05` (RGB565) must come after the relock** or you
get vertical striping → SLPOUT `0x11` → DISPON `0x29`. Do not reorder.
