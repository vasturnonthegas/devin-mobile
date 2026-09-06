#!/bin/sh
# Captures the App Store iPhone screenshot set from a booted Simulator using the DEBUG-only mock API.
# Usage: AppStore/screenshots.sh <path/to/DevinMobile.app> <output-dir> [simulator-udid|booted]
# See AppStore/Metadata.md § Screenshots for what each frame shows.
set -eu

APP=${1:?path to DevinMobile.app}
OUT=${2:?output directory}
DEVICE=${3:-booted}
BUNDLE_ID=ai.devin.mobile
SETTLE=${SETTLE:-6}   # seconds for the mock inbox / transcript to render before the shot

mkdir -p "$OUT"
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi

shoot() { # <file> <launch args...>
  file=$1; shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$DEVICE" screenshot "$OUT/$file" >/dev/null 2>&1
  echo "$OUT/$file"
}

shoot 01-inbox.png -MockAPI
shoot 02-session.png -MockAPI -OpenURL devinmobile://session/devin-mock000
shoot 03-finished.png -MockAPI -OpenURL devinmobile://session/devin-mock002
# No credentials without -MockAPI on a fresh install, so this lands on the sign-in screen. If a real
# token is in the Simulator's Keychain, sign out in Settings first.
shoot 04-onboarding.png

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl status_bar "$DEVICE" clear
