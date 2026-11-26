// Shared headless-Chrome harness for the browser checks (check-puzzles, check-social, check-drag). Serves web/ on localhost, starts a
// fresh Chrome with its own temp profile, and BLOCKS every Supabase request at the browser level, so a test can never write to the
// production leaderboard even if the page isn't in the Social Lab (2026-11-26: a test that failed to enter the lab posted one profile).
import {createServer} from 'node:http';
import {readFile, mkdtemp, rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join, extname, normalize} from 'node:path';
import {fileURLToPath} from 'node:url';

export const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const TYPES = {'.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.wav': 'audio/wav', '.woff2': 'font/woff2', '.webmanifest': 'application/manifest+json'};
export const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function startBrowser({width = 430, height = 932} = {}) {
  const server = createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
    try { const body = await readFile(join(ROOT, path === '/' ? 'index.html' : path)); res.writeHead(200, {'content-type': TYPES[extname(path).toLowerCase()] || 'application/octet-stream'}); res.end(body) } catch { res.writeHead(404); res.end() }
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const profile = await mkdtemp(join(tmpdir(), 'mt-check-'));
  const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, `--window-size=${width},${height}`, '--no-first-run', '--no-default-browser-check', '--mute-audio', 'about:blank'], {stdio: ['ignore', 'ignore', 'pipe']});
  const browserWs = await new Promise((resolve, reject) => { let buf = ''; const t = setTimeout(() => reject(new Error('Chrome did not start')), 15000);
    chrome.stderr.on('data', d => { buf += d; const m = buf.match(/DevTools listening on (ws:\/\/\S+)/); if (m) { clearTimeout(t); resolve(m[1]) } }) });
  const port = new URL(browserWs).port, page = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl); await new Promise((r, j) => { ws.onopen = r; ws.onerror = j });
  let seq = 0; const pending = new Map(), errors = [];
  ws.onmessage = e => { const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { const {resolve, reject} = pending.get(m.id); pending.delete(m.id); m.error ? reject(new Error(m.error.message)) : resolve(m.result) }
    else if (m.method === 'Runtime.exceptionThrown') errors.push(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text) };
  const send = (method, params = {}) => new Promise((resolve, reject) => { const id = ++seq; pending.set(id, {resolve, reject}); ws.send(JSON.stringify({id, method, params})) });
  const evaluate = async expression => { const r = await send('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true}); if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text); return r.result.value };
  const until = async (expression, timeout, what) => { const end = Date.now() + timeout; while (Date.now() < end) { if (await evaluate(expression).catch(() => false)) return; await sleep(100) } throw new Error(`timed out waiting for ${what}`) };
  await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable');
  await send('Network.setBlockedURLs', {urls: ['*supabase.co*', '*supabase*']});
  const go = async (query = '') => { await send('Page.navigate', {url: `${origin}/index.html?noframe${query}`}); await until(`document.readyState==='complete'&&typeof progress==='object'`, 30000, 'the game to load'); await sleep(1200) };
  const touch = (type, touchPoints) => send('Input.dispatchTouchEvent', {type, touchPoints});
  const close = async () => { try { ws.close() } catch {} chrome.kill(); server.close(); await rm(profile, {recursive: true, force: true}).catch(() => {}) };
  return {send, evaluate, until, go, touch, close, errors, origin};
}

// A tiny assertion collector: every check prints PASS/FAIL, and the script exits 1 if anything failed.
export function checker(name) {
  let fails = 0;
  return {
    ok(cond, what, detail) { if (cond) console.log(`  PASS ${what}`); else { fails++; console.log(`  FAIL ${what}${detail !== undefined ? ` (${typeof detail === 'string' ? detail : JSON.stringify(detail)})` : ''}`) } },
    section(t) { console.log(`\n${name}: ${t}`) },
    end() { console.log(fails ? `\n${name}: ${fails} failure(s)` : `\n${name}: all passed`); return fails },
  };
}
