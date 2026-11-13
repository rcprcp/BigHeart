#!/usr/bin/env bash
# Copy the built watch face to a connected Garmin watch.
#
# The Forerunner 265 exposes its storage over MTP, not as a USB block device.
# GNOME/gvfs usually mounts it automatically under /run/user/<uid>/gvfs.
set -euo pipefail
cd "$(dirname "$0")"

PRG="bin/BigHeart.prg"
if [[ ! -f "$PRG" ]]; then
    echo "Build first: ./build.sh" >&2
    exit 1
fi

find_apps_dir() {
    local uid user path found
    uid="$(id -u)"
    user="${USER:-$(id -un)}"
    shopt -s nullglob

    # MTP mounts created by GNOME/gvfs (Forerunner 265).
    for path in /run/user/"$uid"/gvfs/mtp:host=* /run/user/"$uid"/gvfs/*; do
        found="$(find "$path" -maxdepth 4 -type d -path '*/GARMIN/APPS' -print -quit 2>/dev/null || true)"
        if [[ -n "$found" ]]; then
            printf '%s\n' "$found"
            return 0
        fi
    done

    # Watches that still expose FAT mass storage.
    for path in /media/"$user"/* /run/media/"$user"/* /media/* /mnt/*; do
        if [[ -d "$path/GARMIN/APPS" ]]; then
            printf '%s\n' "$path/GARMIN/APPS"
            return 0
        fi
        if [[ -d "$path/APPS" && -f "$path/GarminDevice.xml" ]]; then
            printf '%s\n' "$path/APPS"
            return 0
        fi
    done
    return 1
}

if apps_dir="$(find_apps_dir)"; then
    cp "$PRG" "$apps_dir/BigHeart.prg"
    sync
    echo "Installed $apps_dir/BigHeart.prg"
    echo "Eject the watch, then select Big Heart from the watch-face picker."
    exit 0
fi

cat >&2 <<'MSG'
No Garmin watch filesystem found.

On the watch:
  1. Find USB Mode and select MTP (some firmware says Mass Storage).
     Path is either System -> USB Mode, or Watch Settings -> System ->
     Advanced -> USB Mode, depending on firmware.
     Do not use "Garmin" mode; it only charges / prompts.
     If you cannot find it, leave the default: the watch normally enters MTP
     automatically when connected to a computer.
  2. Use the Garmin data cable, not a charge-only cable.

On this Linux computer:
  * Open Files/Nautilus and look for the watch in the sidebar. GNOME mounts
    it automatically under /run/user/<uid>/gvfs, then run this script again.
  * Or mount it manually with simple-mtpfs:

      sudo apt install simple-mtpfs
      simple-mtpfs --list-devices
      mkdir -p ~/garmin-mtp
      simple-mtpfs ~/garmin-mtp
      find ~/garmin-mtp -type d -name APPS
      cp bin/BigHeart.prg ~/garmin-mtp/GARMIN/APPS/
      fusermount -u ~/garmin-mtp

    On some watches the path is ~/garmin-mtp/Primary/GARMIN/APPS instead.
MSG
exit 1
