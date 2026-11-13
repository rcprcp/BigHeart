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

    # MTP mounts created by GNOME/gvfs (Forerunner 265). The folder is
    # usually "GARMIN/Apps" but casing varies by firmware.
    for path in /run/user/"$uid"/gvfs/mtp:host=*; do
        found="$(find "$path" -maxdepth 4 -type d -ipath '*/GARMIN/APPS' -print -quit 2>/dev/null || true)"
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
        if [[ -d "$path/GARMIN/Apps" ]]; then
            printf '%s\n' "$path/GARMIN/Apps"
            return 0
        fi
        if [[ -d "$path/APPS" && -f "$path/GarminDevice.xml" ]]; then
            printf '%s\n' "$path/APPS"
            return 0
        fi
    done
    return 1
}

copy_to_mtp() {
    local source="$1"
    local apps_dir="$2"
    local uid rel host path uri
    uid="$(id -u)"

    # /run/user/1000/gvfs/mtp:host=091e_50a1_.../Internal Storage/GARMIN/Apps
    # -> mtp://091e_50a1_.../Internal%20Storage/GARMIN/Apps/
    rel="${apps_dir#/run/user/"$uid"/gvfs/}"
    host="${rel%%/*}"
    host="${host#mtp:host=}"
    path="${rel#*/}"
    path="${path// /%20}"
    uri="mtp://${host}/${path}/"

    gio copy -p "$source" "$uri"
}

apps_dir="$(find_apps_dir || true)"
if [[ -z "$apps_dir" ]]; then
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
      cp bin/BigHeart.prg ~/garmin-mtp/GARMIN/Apps/
      fusermount -u ~/garmin-mtp

    On some watches the path is ~/garmin-mtp/Primary/GARMIN/Apps instead.
MSG
    exit 1
fi

if [[ "$apps_dir" == /run/user/"$(id -u)"/gvfs/mtp:host=* ]]; then
    copy_to_mtp "$PRG" "$apps_dir"
else
    cp "$PRG" "$apps_dir/BigHeart.prg"
    sync
fi

local_size="$(stat -c %s "$PRG")"
remote_size="$(stat -c %s "$apps_dir/BigHeart.prg" 2>/dev/null || echo 0)"
if [[ "$local_size" != "$remote_size" ]]; then
    echo "Copy failed: expected $local_size bytes, watch has $remote_size." >&2
    exit 1
fi

echo "Installed $apps_dir/BigHeart.prg ($remote_size bytes)"
echo "Eject the watch (press Back on the connect screen), then select Big Heart"
echo "from the watch-face picker."
