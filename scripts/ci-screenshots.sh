#!/usr/bin/env bash
# Screenshots of the app in the iOS simulator, at a few places in Singapore, so that UI changes
# can be reviewed on a pull request without a Mac. Run by .github/workflows/ios.yml after the
# simulator build (Debug: the -ui… launch arguments below only exist in debug builds).
#
#   scripts/ci-screenshots.sh path/to/SingaSmoke.app output-folder
#
# SHOT_SET=quick (default) takes the screens that change most; SHOT_SET=full takes every one.
set -euo pipefail

APP="${1:?path to SingaSmoke.app}"
OUT="${2:-screenshots}"
BUNDLE_ID=uk.riskybusinesses.singasmoke
mkdir -p "$OUT"

# The newest iPhone "Pro" simulator (6.3", the size most people hold). Booted here, after the
# build: booting it during the compilation slowed both down on the runner's few cores.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [(runtime, d) for runtime, ds in devices.items() if ".iOS-" in runtime
          for d in ds if d["name"].startswith("iPhone") and "Pro" in d["name"] and "Max" not in d["name"]]
phones.sort(key=lambda p: [int(x) for x in p[0].rsplit("iOS-", 1)[1].split("-")])
print(phones[-1][1]["udid"])')
echo "Simulator: $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID"
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# Passed to every launch: the appearance is also forced inside the app, as the simulator's own
# switch does not always reach it.
APPEARANCE_ARGS=""

# shoot NAME LAT,LON SECONDS [launch arguments…]   (FIRST_LAUNCH=1: keep the first-launch warning)
shoot() {
  local name=$1 place=$2 wait=$3
  shift 3
  local skip="-uiSkipDisclaimer YES"
  if [ "${FIRST_LAUNCH:-0}" = 1 ]; then skip=""; fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl location "$UDID" set "$place"
  # shellcheck disable=SC2086
  xcrun simctl launch "$UDID" "$BUNDLE_ID" $skip $APPEARANCE_ARGS "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "✓ $name"
}

ORCHARD=1.30400,103.83240   # Orchard Road: no-smoking zone, NEA yellow boxes around
GARDENS=1.31380,103.81590   # Singapore Botanic Gardens: smoke-free park
JURONG=1.33330,103.74220    # Jurong East: ordinary streets, bus stops, shops
ABROAD=3.13900,101.68690    # Kuala Lumpur: outside Singapore, the map stays on the whole island

# The appearance switch can take a moment to reach running services: wait, then check it.
appearance() {
  xcrun simctl ui "$UDID" appearance "$1"
  APPEARANCE_ARGS="-uiAppearance $1"
  sleep 3
  echo "Appearance: $(xcrun simctl ui "$UDID" appearance)"
}

SET="${SHOT_SET:-quick}"
echo "Screenshot set: $SET"

# The app waits for its data and the nearest places before opening a sheet (-ui… arguments),
# so a few seconds are enough; the map tiles and walking routes come from the network.
appearance light
shoot 01-orchard "$ORCHARD" 9
[ "$SET" = full ] && shoot 01b-orchard-status "$ORCHARD" 9 -uiExpandStatus YES
[ "$SET" = full ] && shoot 02-botanic-gardens "$GARDENS" 9
[ "$SET" = full ] && shoot 03-jurong-east "$JURONG" 9
shoot 04-spot-sheet "$ORCHARD" 10 -uiOpenFirstSpot YES
shoot 05-spot-list "$ORCHARD" 10 -uiShowList YES
shoot 06-buy "$JURONG" 9 -uiMode buy
[ "$SET" = full ] && shoot 06b-buy-list "$JURONG" 10 -uiMode buy -uiShowList YES
shoot 07-guidance "$JURONG" 13 -uiGuideFirstSpot YES
shoot 07b-guidance-overview "$JURONG" 16 -uiGuideFirstSpot YES -uiGuideOverview YES
shoot 08-whole-island "$ABROAD" 9
[ "$SET" = full ] && shoot 08b-district "$JURONG" 9 -uiSpanMeters 3000   # ~3 km wide, ~6.5 km tall
[ "$SET" = full ] && shoot 09-about "$JURONG" 10 -uiShowInfo YES
[ "$SET" = full ] && FIRST_LAUNCH=1 shoot 10-first-launch "$JURONG" 6
appearance dark
shoot 11-orchard-dark "$ORCHARD" 9
[ "$SET" = full ] && shoot 12-buy-dark "$JURONG" 9 -uiMode buy
shoot 13-spot-sheet-dark "$JURONG" 10 -uiOpenFirstSpot YES
[ "$SET" = full ] && shoot 14-guidance-dark "$ORCHARD" 13 -uiGuideFirstSpot YES

# Lighter files for the review.
sips -Z 1200 "$OUT"/*.png >/dev/null
ls -la "$OUT"
