#!/bin/zsh
# Reset the simulator for one demo persona.
#   prep_sim.sh <light|dark> <media files... (added oldest -> newest)>
# Erases the device so the photo library contains exactly these files, in a known order.
set -e
U=${SIM_UDID:-364925EE-28C3-4016-A3EF-DA136F7BE42F}
APP=${APP_PATH:-$HOME/Library/Developer/XcodeBuildMCP/workspaces/malik-ea67663a7006/DerivedData/ClothingOnU-1c4bd2a4ef53/Build/Products/Debug-iphonesimulator/ClothingOnU.app}
mode=$1; shift
xcrun simctl shutdown $U 2>/dev/null || true
xcrun simctl erase $U
# Show the on-screen keyboard when typing (looks real on video).
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcrun simctl boot $U
xcrun simctl bootstatus $U >/dev/null
xcrun simctl ui $U appearance $mode
xcrun simctl status_bar $U override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
tmp=$(mktemp -d)
i=0
for f in "$@"; do
  i=$((i+1))
  # Strip EXIF so the library orders by import time, not by original capture date.
  magick "$f" -strip "$tmp/$(printf %02d $i)-$(basename "$f")"
  xcrun simctl addmedia $U "$tmp/$(printf %02d $i)-$(basename "$f")"
  sleep 1.2
done
xcrun simctl install $U "$APP"
echo "ready: $U ($mode, $# media)"
