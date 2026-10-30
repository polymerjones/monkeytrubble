#!/bin/zsh
# Cold-launch time check for the Android app (Apple's perf talk: test launch time every release, especially after adding an SDK).
# Times the build already installed on the connected phone: a cold start (`am start -W -S`) RUNS times, and compares the median
# TotalTime (to the first drawn frame) with tools/launch-baseline.txt. More than 25% and 100ms slower fails (exit 1).
# It doesn't install anything: a release build signed with the upload key can't replace a debug build without an uninstall, which
# would delete the saved game. For release numbers, install the build from the Play test track first. The numbers depend on the phone,
# so keep one baseline per phone.
# Run: MonkeyTrubbleAndroid/tools/launch-time.sh            (compare with the baseline)
#      MonkeyTrubbleAndroid/tools/launch-time.sh --update   (save this phone's numbers as the new baseline)
set -e
ADB=${ADB:-~/Library/Android/sdk/platform-tools/adb}
APP=com.paulfisher.monkeytrubble
RUNS=5
BASELINE=${0:A:h}/launch-baseline.txt

$ADB get-state >/dev/null 2>&1 || { echo "No phone connected (adb devices)."; exit 2 }
model=$($ADB shell getprop ro.product.model | tr -d '\r')
version=$($ADB shell dumpsys package $APP | grep -m1 versionCode | tr -d '\r' | awk '{print $1}')
debuggable=$($ADB shell dumpsys package $APP | grep -m1 -o 'DEBUGGABLE' || true)
echo "$model, $APP $version ${debuggable:+(debug build)}"

times=()
for i in $(seq $RUNS); do
  ms=$($ADB shell am start -W -S -n $APP/.MainActivity | tr -d '\r' | awk -F': ' '/TotalTime/{print $2}')
  [[ -n $ms ]] || { echo "Launch $i didn't report a time."; exit 2 }
  times+=($ms)
  echo "  run $i: ${ms}ms"
  sleep 2
done
median=$(printf '%s\n' $times | sort -n | sed -n "$(( (RUNS + 1) / 2 ))p")
echo "median: ${median}ms"

if [[ $1 == --update ]]; then
  echo "$median $model" > $BASELINE
  echo "Saved as the baseline."
  exit 0
fi
[[ -f $BASELINE ]] || { echo "No baseline yet: run with --update."; exit 0 }
read base baseModel < $BASELINE
[[ $baseModel == $model ]] || echo "Note: the baseline was taken on $baseModel."
if (( median > base * 125 / 100 && median - base > 100 )); then
  echo "SLOWER: ${median}ms vs baseline ${base}ms."
  exit 1
fi
echo "OK (baseline ${base}ms)."
