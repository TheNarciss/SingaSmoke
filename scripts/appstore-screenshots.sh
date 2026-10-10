#!/usr/bin/env bash
# App Store screenshots: the 6.9" iPhone at full resolution (1320 × 2868), clean status bar.
# Run by .github/workflows/appstore.yml on a Debug simulator build (the -ui… launch arguments
# that set up each screen only exist in debug builds). The order of the files is the order on
# the App Store.
#
#   scripts/appstore-screenshots.sh path/to/SingaSmoke.app output-folder
set -euo pipefail

APP="${1:?path to SingaSmoke.app}"
OUT="${2:?output folder}"
BUNDLE_ID=uk.riskybusinesses.singasmoke
mkdir -p "$OUT"
rm -f "$OUT"/*.png

# The newest iPhone "Pro Max" simulator: the 6.9" display App Store Connect asks for.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [(runtime, d) for runtime, ds in devices.items() if ".iOS-" in runtime
          for d in ds if d["name"].startswith("iPhone") and d["name"].endswith("Pro Max")]
phones.sort(key=lambda p: [int(x) for x in p[0].rsplit("iOS-", 1)[1].split("-")])
print(phones[-1][1]["udid"])')
echo "Simulator: $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID"
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

APPEARANCE_ARGS="-uiAppearance light"

# shoot NAME LAT,LON SECONDS [launch arguments…]
shoot() {
  local name=$1 place=$2 wait=$3
  shift 3
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl location "$UDID" set "$place"
  # shellcheck disable=SC2086
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiSkipDisclaimer YES $APPEARANCE_ARGS "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "✓ $name"
}

ORCHARD=1.30400,103.83240   # Orchard Road: no-smoking zone, NEA yellow boxes around
GARDENS=1.31380,103.81590   # Singapore Botanic Gardens: smoke-free park

xcrun simctl ui "$UDID" appearance light
shoot 1-can-i-smoke-here "$ORCHARD" 12
shoot 2-designated-smoking-area "$ORCHARD" 15 -uiOpenOfficialSpot YES
shoot 3-nearest-by-walking-time "$ORCHARD" 12 -uiShowList YES
shoot 4-walking-directions "$ORCHARD" 16 -uiGuideFirstSpot YES
xcrun simctl ui "$UDID" appearance dark
APPEARANCE_ARGS="-uiAppearance dark"
shoot 5-parks-and-zones "$GARDENS" 12 -uiExpandStatus YES

# App Store Connect refuses any other size for the 6.9" slot.
for f in "$OUT"/*.png; do
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/ {print $2}')
  if [ "$w" != 1320 ] || [ "$h" != 2868 ]; then echo "::error::$f is ${w}×${h}, expected 1320×2868"; exit 1; fi
done
ls -la "$OUT"
