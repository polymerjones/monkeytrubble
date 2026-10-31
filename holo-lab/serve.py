#!/usr/bin/env python3
"""The Lab's local server: like `python3 -m http.server`, but every response says no-store, so Safari never shows an old copy of
web/index.html (it cached one heuristically and the Puzzle Feel sliders seemed to do nothing, 2026-10-31). Run from the repo root."""
import http.server, sys
class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8790
http.server.ThreadingHTTPServer(('127.0.0.1', port), NoCache).serve_forever()
