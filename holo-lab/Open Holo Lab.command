#!/bin/sh
# Double-click to open the Holo Lab: serves the repo on http://localhost:8790 and opens the lab in the browser. Close this window to stop it.
cd "$(dirname "$0")/.."
PORT=8790
URL="http://localhost:$PORT/holo-lab/"
if lsof -ti tcp:$PORT >/dev/null 2>&1; then open "$URL"; exit 0; fi
(sleep 1; open "$URL") &
echo "Holo Lab is running at $URL (close this window to stop it)."
exec python3 holo-lab/serve.py $PORT
