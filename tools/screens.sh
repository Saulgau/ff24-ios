#!/bin/bash
# Automatische Bildschirmfotos im Simulator (Apple TV + iPhone/iPad in mehreren Größen).
set -u
mkdir -p shots
pick_rt() { xcrun simctl list runtimes -j | python3 -c "import json,sys;r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='$1' and x['isAvailable']];print(r[-1]['identifier'] if r else '')"; }
pick_dt() { xcrun simctl list devicetypes -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devicetypes']; want=sys.argv[1:]
for w in want:
  m=[x for x in d if w.lower() in x['name'].lower()]
  if m: print(m[-1]['identifier']); break" "$@"; }
shoot() { # name devtype runtime app bundle screens...
  local name=$1 dt=$2 rt=$3 app=$4 bid=$5; shift 5
  [ -n "$dt" ] && [ -n "$rt" ] || { echo "SKIP $name"; return; }
  local dev; dev=$(xcrun simctl create "$name" "$dt" "$rt") || return
  xcrun simctl boot "$dev"; xcrun simctl bootstatus "$dev" -b >/dev/null
  xcrun simctl ui "$dev" appearance dark 2>/dev/null || true
  xcrun simctl install "$dev" "$app"
  for sc in "$@"; do
    local base=${sc%%+*} args=(-ff24screen "${sc%%+*}")
    [[ $sc == *+focus ]] && args+=(-ff24focus)
    xcrun simctl launch "$dev" "$bid" "${args[@]}" >/dev/null
    sleep 20
    xcrun simctl io "$dev" screenshot "shots/$name-$sc.png" >/dev/null 2>&1
    if [[ $sc == *+focus ]]; then
      # Fernbedienung nachahmen: Simulator nach vorn, Pfeil runter (Fokus auf erste Reihe), dann rechts
      osascript -e 'tell application "Simulator" to activate' -e 'delay 1' -e 'tell application "System Events" to key code 125' >/dev/null 2>&1 || echo "Tastendruck nicht moeglich"
      sleep 0.25; xcrun simctl io "$dev" screenshot "shots/$name-$sc-zoom.png" >/dev/null 2>&1
      sleep 2; xcrun simctl io "$dev" screenshot "shots/$name-$sc-fokus.png" >/dev/null 2>&1
      osascript -e 'tell application "System Events" to key code 124' >/dev/null 2>&1
      sleep 12; xcrun simctl io "$dev" screenshot "shots/$name-$sc-trailer.png" >/dev/null 2>&1
    fi
    xcrun simctl terminate "$dev" "$bid" 2>/dev/null
  done
  xcrun simctl shutdown "$dev"; xcrun simctl delete "$dev"
}
TV=build/Build/Products/Release-appletvsimulator/FilmFrei24TV.app
IOS=build/Build/Products/Release-iphonesimulator/FilmFrei24.app
RTV=$(pick_rt tvOS); RIOS=$(pick_rt iOS)
if [ -d "$TV" ]; then open -a Simulator 2>/dev/null; sleep 3
  shoot appletv "$(pick_dt 'Apple TV 4K (3rd' 'Apple TV 4K')" "$RTV" "$TV" com.filmfrei24.tv home home+focus detail-film detail-serie filme login; fi
if [ -d "$IOS" ]; then
  shoot iphone-se "$(pick_dt 'iPhone SE (3rd' 'iPhone SE')" "$RIOS" "$IOS" com.filmfrei24.app home detail-film detail-serie login
  shoot iphone-promax "$(pick_dt 'iPhone 16 Pro Max' 'Pro Max')" "$RIOS" "$IOS" com.filmfrei24.app home detail-film detail-serie
  shoot ipad-mini "$(pick_dt 'iPad mini (A17' 'iPad mini')" "$RIOS" "$IOS" com.filmfrei24.app home detail-film
  shoot ipad-pro13 "$(pick_dt 'iPad Pro 13' 'iPad Pro (12.9' 'iPad Pro')" "$RIOS" "$IOS" com.filmfrei24.app home detail-film detail-serie
fi
ls -la shots
