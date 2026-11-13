// node ipadextras.mjs (seasonal, POLY and hero shots) <url> <outdir> <lang>: App Store screenshots at the 13-inch iPad size (1032x1376 @2x = 2064x2752).
import {spawn} from 'node:child_process';
import {writeFileSync, mkdirSync, rmSync} from 'node:fs';
const [url, out, lang = 'en'] = process.argv.slice(2);
mkdirSync(out, {recursive: true});
const prof = out + '/prof'; rmSync(prof, {recursive: true, force: true});
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', '--remote-debugging-port=9334', '--user-data-dir=' + prof, '--hide-scrollbars', '--mute-audio', 'about:blank'], {stdio: 'ignore'});
const sleep = ms => new Promise(r => setTimeout(r, ms));
await sleep(1500);
const tabs = await (await fetch('http://127.0.0.1:9334/json')).json();
const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const pend = {};
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend[m.id]) { pend[m.id](m); delete pend[m.id]; } };
const send = (method, params = {}) => new Promise(r => { pend[++id] = r; ws.send(JSON.stringify({id, method, params})); });
const ev = async expr => { const r = await send('Runtime.evaluate', {expression: expr, awaitPromise: true, returnByValue: true}); if (r.result?.exceptionDetails) console.log('ERR', expr.slice(0, 60), r.result.exceptionDetails.exception?.description?.slice(0, 200)); return r.result?.result?.value; };
await send('Page.enable');
// Pretend to be the iOS app (no dev mode, no desktop frame).
await send('Page.addScriptToEvaluateOnNewDocument', {source: "window.__monkeyDebugBuild=false;window.webkit={messageHandlers:new Proxy({},{get:()=>({postMessage(){}})})}"});
await send('Emulation.setDeviceMetricsOverride', {width: 1032, height: 1376, deviceScaleFactor: 2, mobile: true});
await send('Emulation.setTouchEmulationEnabled', {enabled: true});
let cur = url;
const load = async (u = cur) => { cur = u; await send('Page.navigate', {url: u}); await sleep(6000); };
const shot = async name => { await sleep(500); const s = await send('Page.captureScreenshot', {format: 'png'}); writeFileSync(`${out}/${name}.png`, Buffer.from(s.result.data, 'base64')); console.log(name); };

const XMAS = url + (url.includes('?') ? '&' : '?') + 'today=2026-12-05';
await load();
await ev(`(()=>{const i=document.querySelector('#nameInput');if(i&&i.offsetParent){i.value='JungleKing';i.dispatchEvent(new Event('input',{bubbles:true}));document.querySelector('#nameSave').click()}})()`);
await sleep(1500);
const setup = (lv, season) => ev(`try{closeWelcome()}catch(e){};progress.level=${lv};progress.streak={...progress.streak,count:6,lastDate:localDate()};progress.notesSeen=RELEASE_NOTES.version;progress.tutorialDone=true;progress.tutorialV=TUTORIAL_VERSION;progress.mapIntro=true;progress.tips=[...new Set(['joker','vision','poly','undo','shuffle','hint','counts','continue',...TIPS.map(t=>t.id)])];progress.settings.season='${season}';saveProgress();`);
const play = async (lv, season, u) => { await setup(lv, season); await load(u); await ev(`try{closeWelcome()}catch(e){}`); await sleep(1500); await ev(`playFromHome()`); await sleep(6000); console.log(lv, season, await ev(`state.pack`)); };
// Halloween level
await play(14, 'only', url); await shot('x-halloween');
// Hero spotlight on a Halloween card
await ev(`(()=>{const t=state.tiles.find(t=>t.symbol!==POLY&&CARD_DATA[t.symbol]&&!CARD_DATA[t.symbol].joker);featuredSymbol=t.symbol;renderFeatured()})()`); await sleep(800);
await ev(`openLightbox()`); await sleep(3000); await shot('x-hero-halloween');
// Christmas level (date faked to Dec 5)
await play(22, 'on', XMAS); await shot('x-christmas');
await ev(`(()=>{const t=state.tiles.find(t=>t.symbol!==POLY&&CARD_DATA[t.symbol]);featuredSymbol=t.symbol;renderFeatured()})()`); await sleep(800);
await ev(`openLightbox()`); await sleep(3000); await shot('x-hero-christmas');
// POLY bursts: Christmas and jungle, a few frames each
await play(22, 'on', XMAS); ev(`state.devAssisted=true;firePoly(null)`);
for (const t of [500, 500, 600, 800]) { await sleep(t); await shot('x-poly-xmas-' + t + '-' + Date.now() % 1000); }
await play(27, 'off', url); ev(`state.devAssisted=true;firePoly(null)`);
for (const t of [500, 500, 600, 800]) { await sleep(t); await shot('x-poly-jungle-' + t + '-' + Date.now() % 1000); }
ws.close(); chrome.kill();
