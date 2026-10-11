#!/usr/bin/env bash
# App Store screenshots at full resolution, clean status bar, on two iPhones:
#   6.3in-*  1206 × 2622  "iPhone with Dynamic Island (medium display)", the size App Store Connect requires;
#   6.9in-*  1320 × 2868  "large display", shown as is on the biggest iPhones instead of scaled.
# fastlane deliver puts each file in its App Store Connect slot by its pixel size; within a slot, the
# number after the prefix is the order on the App Store.
# Run by .github/workflows/appstore.yml on a Debug simulator build (the -ui… launch arguments
# that set up each screen only exist in debug builds).
#
#   scripts/appstore-screenshots.sh path/to/SingaSmoke.app output-folder
set -euo pipefail

APP="${1:?path to SingaSmoke.app}"
OUT="${2:?output folder}"
BUNDLE_ID=uk.riskybusinesses.singasmoke
mkdir -p "$OUT"
rm -f "$OUT"/*.png

ORCHARD=1.30400,103.83240   # Orchard Road: no-smoking zone, NEA yellow boxes around
GARDENS=1.31380,103.81590   # Singapore Botanic Gardens: smoke-free park

# newest_iphone SUFFIX: the newest iPhone simulator whose name ends with SUFFIX (" Pro", " Pro Max").
newest_iphone() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
suffix = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
phones = [(runtime, d) for runtime, ds in devices.items() if ".iOS-" in runtime
          for d in ds if d["name"].startswith("iPhone") and d["name"].endswith(suffix)]
phones.sort(key=lambda p: ([int(x) for x in p[0].rsplit("iOS-", 1)[1].split("-")], p[1]["name"]))
print(phones[-1][1]["udid"])' "$1"
}

# shoot NAME LAT,LON SECONDS [launch arguments…], on $UDID, saved as $OUT/$PREFIX-NAME.png
shoot() {
  local name=$1 place=$2 wait=$3
  shift 3
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl location "$UDID" set "$place"
  # shellcheck disable=SC2086
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiSkipDisclaimer YES $APPEARANCE_ARGS "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$PREFIX-$name.png" >/dev/null 2>&1
  echo "✓ $PREFIX-$name"
}

# shoot_on PREFIX NAME-SUFFIX WIDTH HEIGHT: the five App Store screens on one iPhone.
shoot_on() {
  PREFIX=$1
  UDID=$(newest_iphone "$2")
  local width=$3 height=$4
  echo "$PREFIX: simulator $UDID"
  xcrun simctl boot "$UDID" || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID"
  xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

  xcrun simctl ui "$UDID" appearance light
  APPEARANCE_ARGS="-uiAppearance light"
  shoot 1-can-i-smoke-here "$ORCHARD" 12
  shoot 2-designated-smoking-area "$ORCHARD" 15 -uiOpenOfficialSpot YES
  shoot 3-nearest-by-walking-time "$ORCHARD" 12 -uiShowList YES
  shoot 4-walking-directions "$ORCHARD" 16 -uiGuideFirstSpot YES
  xcrun simctl ui "$UDID" appearance dark
  APPEARANCE_ARGS="-uiAppearance dark"
  shoot 5-parks-and-zones "$GARDENS" 12 -uiExpandStatus YES

  # App Store Connect refuses any other size in the slot.
  for f in "$OUT/$PREFIX"-*.png; do
    w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')
    h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/ {print $2}')
    if [ "$w" != "$width" ] || [ "$h" != "$height" ]; then echo "::error::$f is ${w}×${h}, expected ${width}×${height}"; exit 1; fi
  done
  xcrun simctl shutdown "$UDID" || true
}

shoot_on 6.3in " Pro" 1206 2622       # newest iPhone Pro: medium display, required
shoot_on 6.9in " Pro Max" 1320 2868   # newest iPhone Pro Max: large display
ls -la "$OUT"
