# Big Heart

A Garmin Connect IQ watch face for the **Forerunner 265** that shows heart rate
in the largest red numerals that fit the round 416×416 AMOLED screen, with SpO2
in blue underneath. A small clock sits at the top.

![Big Heart preview](docs/preview.png)

## Layout

- **Heart rate** — red, up to 195 px tall (156 px for a three-digit value).
- **SpO2** — blue, 104 px tall.
- **Time** — small grey clock at the top, 12- or 24-hour according to the watch.
- No labels: colour identifies the values.

The numerals use a normal condensed sans font (Liberation Sans Narrow Bold)
converted to large 1-bit bitmap fonts, so they stay crisp and do not need a
huge font atlas at runtime.

## Build

The project uses the Connect IQ SDK and a developer key:

```bash
./build.sh
```

This produces `bin/BigHeart.prg`. Override the defaults with
`CONNECTIQ_SDK=/path/to/sdk` and `CONNECTIQ_KEY=/path/to/developer_key.der`
if needed.

The fonts in `resources/fonts/` are generated and committed. To recreate them
after changing a size:

```bash
python3 tools/make_fonts.py
```

`tools/preview.py` renders the layout to PNG without the simulator.

## Install on the Forerunner 265

The Forerunner 265 exposes its storage over **MTP**, not as a normal USB
drive. Linux therefore will not show it as a block device in `lsblk`.

1. Build the app.
2. On the watch, find **USB Mode** and choose **MTP** (some firmware labels it
   *Mass Storage*). Do not use *Garmin* mode. Depending on firmware the path is
   either **UP → System → USB Mode** or **UP → Watch Settings → System →
   Advanced → USB Mode**. If you cannot find it, leave the default: the watch
   normally enters MTP automatically when connected to a computer.
3. Connect the watch with the Garmin data cable, not a charge-only cable.
4. On Linux, GNOME Files normally mounts the watch automatically. Then run
   `./install.sh`. It finds both GNOME's MTP mount and older FAT-style Garmin
   mounts.
5. If the watch does not appear, use an MTP client manually:

   ```bash
   sudo apt install simple-mtpfs
   simple-mtpfs --list-devices
   mkdir -p ~/garmin-mtp
   simple-mtpfs ~/garmin-mtp
   find ~/garmin-mtp -type d -name APPS
   cp bin/BigHeart.prg ~/garmin-mtp/GARMIN/APPS/
   fusermount -u ~/garmin-mtp
   ```

   Some watches nest the path as `~/garmin-mtp/Primary/GARMIN/APPS`.
6. Eject the watch, then choose **Big Heart** from the watch-face picker
   (Settings → Appearance → Watch Faces). A reboot may be needed on some
   firmware versions.
7. Accept the sensor-history permission prompt the first time it runs.

To keep the values visible continuously, enable **Always On Display** in the
watch's display settings.

## How the values update

A Connect IQ watch face cannot switch the optical sensors on by itself. The
face reads Garmin's sensor history:

- Heart rate comes from the watch's normal wrist-HR sampling (typically about
  once a minute).
- SpO2 only appears as often as Pulse Ox is configured to measure it. Set
  **Pulse Ox** to *All Day* (more battery use) or *During Sleep*. With Pulse Ox
  off or set to manual, SpO2 will usually show `--` or a value from the last
  measurement.
- When no valid sample exists, the value is shown as `--`.

This is normal for watch faces. For beat-to-beat data you need an activity
profile or a data field while recording an activity, which is a different app
type.

## Always-on (ambient) mode

The Forerunner 265 has an AMOLED panel with Garmin's burn-in protection: an
always-on face must stay dim and must not leave too many pixels lit. In
ambient mode this face keeps the same normal font and layout, but uses smaller
numerals (120 px HR, 72 px SpO2), dimmer colours, and shifts the readout a few
pixels each minute. That keeps the numbers visible all the time without
tripping the panel protection. Normal viewing mode uses the full-size
numerals.

![Ambient preview](docs/preview-ambient.png)
