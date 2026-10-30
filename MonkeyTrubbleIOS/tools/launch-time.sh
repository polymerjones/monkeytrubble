#!/bin/zsh
# Launch-time check for the iPhone app (Apple's perf talk: test launch time every release, especially after adding an SDK).
# Records RUNS cold launches with Instruments' App Launch template (xctrace) on the connected or wireless iPhone, sums the launch
# phases up to the end of "Initial Frame Rendering" (time to the first frame), and compares the median with tools/launch-baseline.txt:
# more than 25% and 50ms slower fails (exit 1). It times whatever build is installed (Debug from /ship, or the TestFlight build);
# the phone must be unlocked. Each run takes about half a minute. One baseline per phone (the numbers depend on it).
# Run: MonkeyTrubbleIOS/tools/launch-time.sh            (compare with the baseline)
#      MonkeyTrubbleIOS/tools/launch-time.sh --update   (save this phone's numbers as the new baseline)
set -e
APP=com.paulfisher.MonkeyTrubble
RUNS=${RUNS:-3}
BASELINE=${0:A:h}/launch-baseline.txt
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

DEVICE=${DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && (/available \(paired\)/ || /connected/) {for(i=1;i<=NF;i++) if($i=="(UDID)") print $(i-1)}' | head -1)}
[[ -n $DEVICE ]] || { echo "No iPhone available (xcrun devicectl list devices)."; exit 2 }
model=$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | sed -E 's/ +[0-9A-F-]{20,}.*//' | xargs)
echo "$model ($DEVICE)"

times=()
for i in $(seq $RUNS); do
  out=$TMP/run$i.trace
  # xctrace can exit non-zero over a harmless warning (the sampling-rate note), so the saved trace is what counts.
  xcrun xctrace record --template 'App Launch' --device "$DEVICE" --time-limit 6s --output "$out" --launch -- $APP >$TMP/run$i.log 2>&1 || true
  [[ -d $out ]] || { echo "Run $i: recording failed (is the phone unlocked?): $(tail -1 $TMP/run$i.log)"; exit 2 }
  xcrun xctrace export --input "$out" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="life-cycle-period"]' > $TMP/run$i.xml 2>/dev/null
  # Time to first frame: from the first launch phase's start to the end of Initial Frame Rendering. The table's column order
  # changes between recordings, so each row's start time and duration are found by their format, not their position.
  ms=$(python3 -I - $TMP/run$i.xml <<'EOF'
import sys,re
x=open(sys.argv[1]).read();ids={}
for m in re.finditer(r'<([\w-]+) id="(\d+)"(?: fmt="([^"]*)")?(?:>([^<]*)<)?',x):ids[m.group(2)]=m.group(3) or m.group(4) or ''
def ms(v):
    m=re.fullmatch(r'([\d.]+) (µs|ms|s)',v.strip());return float(m.group(1))*{'µs':.001,'ms':1,'s':1000}[m.group(2)] if m else None
def at(v):
    m=re.fullmatch(r'(\d+):(\d+)\.(\d+)\.(\d+)',v.strip());return (int(m.group(1))*60+int(m.group(2)))*1000+int(m.group(3))+int(m.group(4))/1000 if m else None
first=None
for r in re.findall(r'<row>(.*?)</row>',x,re.S):
    cells=[c[2] or c[4] or ids.get(c[3],'') for c in re.findall(r'<([\w-]+)(?: id="(\d+)")?(?: fmt="([^"]*)")?(?: ref="(\d+)")?(?:/>|>([^<]*)</\1>)?',r)]
    start=next((at(c) for c in cells if at(c) is not None),None);dur=next((ms(c) for c in cells if ms(c) is not None),None)
    if start is None or dur is None:continue
    if first is None:first=start
    if any('Initial Frame Rendering' in c for c in cells):print(round(start+dur-first));break
else:print(0)
EOF
)
  [[ $ms -gt 0 ]] || { echo "Run $i: no launch phases in the trace."; exit 2 }
  times+=($ms)
  echo "  run $i: ${ms}ms"
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
if (( median > base * 125 / 100 && median - base > 50 )); then
  echo "SLOWER: ${median}ms vs baseline ${base}ms ($baseModel)."
  exit 1
fi
echo "OK (baseline ${base}ms, $baseModel)."
