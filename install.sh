#!/usr/bin/env bash
# Copy the built watch face to a mounted Garmin watch.
set -euo pipefail
cd "$(dirname "$0")"

PRG="bin/BigHeart.prg"
if [[ ! -f "$PRG" ]]; then
    echo "Build first: ./build.sh" >&2
    exit 1
fi

find_device() {
    local user="${USER:-$(id -un)}"
    local mount
    shopt -s nullglob
    for mount in /media/"$user"/* /run/media/"$user"/* /media/* /mnt/*; do
        if [[ -d "$mount/GARMIN/APPS" && -f "$mount/GARMIN/GarminDevice.xml" ]]; then
            printf '%s\n' "$mount"
            return 0
        fi
        if [[ -d "$mount/APPS" && -f "$mount/GarminDevice.xml" ]]; then
            printf '%s\n' "$mount"
            return 0
        fi
    done
    return 1
}

if ! mount="$(find_device)"; then
    echo "No mounted Garmin watch found." >&2
    echo "Connect the Forerunner 265 by USB, wait for it to mount, then run this again." >&2
    exit 1
fi

if [[ -d "$mount/GARMIN/APPS" ]]; then
    destination="$mount/GARMIN/APPS/BigHeart.prg"
else
    destination="$mount/APPS/BigHeart.prg"
fi

cp "$PRG" "$destination"
sync
echo "Installed $destination"
echo "Eject the watch, then select Big Heart from the watch-face picker."
