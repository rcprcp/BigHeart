#!/usr/bin/env bash
# Build the Big Heart Live direct-sensor watch app for the Forerunner 265.
set -euo pipefail
cd "$(dirname "$0")"

SDK="${CONNECTIQ_SDK:-$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")}"
KEY="${CONNECTIQ_KEY:-$HOME/.Garmin/ConnectIQ/developer_key.der}"

mkdir -p bin
"$SDK/bin/monkeyc" -f liveapp/monkey.jungle -d fr265 -o bin/BigHeartLive.prg -y "$KEY" -w
echo "Built bin/BigHeartLive.prg"
