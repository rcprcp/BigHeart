#!/usr/bin/env bash
# Build the Big Heart watch face for the Forerunner 265.
set -euo pipefail
cd "$(dirname "$0")"

SDK="${CONNECTIQ_SDK:-$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")}"
KEY="${CONNECTIQ_KEY:-$HOME/.Garmin/ConnectIQ/developer_key.der}"

if [[ ! -x "$SDK/bin/monkeyc" ]]; then
    echo "monkeyc not found in $SDK" >&2
    echo "Set CONNECTIQ_SDK to your Connect IQ SDK directory." >&2
    exit 1
fi
if [[ ! -f "$KEY" ]]; then
    echo "Developer key not found at $KEY" >&2
    echo "Set CONNECTIQ_KEY to your developer_key.der." >&2
    exit 1
fi

mkdir -p bin
"$SDK/bin/monkeyc" -f monkey.jungle -d fr265 -o bin/BigHeart.prg -y "$KEY" -w
echo "Built bin/BigHeart.prg"
