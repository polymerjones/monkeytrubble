// node ipadcdp.mjs <url> <outdir> <lang>: App Store screenshots at the 13-inch iPad size (1032x1376 @2x = 2064x2752).
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
const load = async () => { await send('Page.navigate', {url}); await sleep(6000); };
const shot = async name => { await sleep(500); const s = await send('Page.captureScreenshot', {format: 'png'}); writeFileSync(`${out}/${name}.png`, Buffer.from(s.result.data, 'base64')); console.log(name); };
await load();
await ev(`(()=>{const i=document.querySelector('#nameInput');if(i&&i.offsetParent){i.value='JungleKing';i.dispatchEvent(new Event('input',{bubbles:true}));document.querySelector('#nameSave').click()}})()`);
await sleep(1500);
await ev(`try{closeWelcome()}catch(e){};progress.level=12;progress.streak={...progress.streak,count:6,lastDate:localDate()};progress.notesSeen=RELEASE_NOTES.version;progress.tutorialDone=true;progress.tutorialV=TUTORIAL_VERSION;progress.mapIntro=true;progress.tips=[...new Set(['joker','vision','poly','undo','shuffle','hint','counts','continue',...TIPS.map(t=>t.id)])];saveProgress();`);
if (lang === 'es') await ev(`try{setLang('es')}catch(e){document.querySelectorAll('button').forEach(b=>{if(/ESPAÑOL/.test(b.textContent))b.click()})}`);
await load();
await ev(`try{closeWelcome()}catch(e){}`); await sleep(2500);
await shot('01-home');
for (const [lv, name] of [[12, '02-level'], [27, '03-level-27'], [37, '04-level-37']]) {
  await ev(`progress.level=${lv};saveProgress()`); await load(); await ev(`try{closeWelcome()}catch(e){}`); await sleep(1500);
  await ev(`playFromHome()`); await sleep(6000);
  await shot(name);
}
await ev(`progress.level=12;saveProgress()`);
await load(); await ev(`try{closeWelcome()}catch(e){}`); await sleep(1500);
await ev(`openPuzzle()`); await sleep(4000);
await shot('05-puzzles');
await load(); await ev(`try{closeWelcome()}catch(e){}`); await sleep(1500);
ev(`playChestScene({preview:true})`); await sleep(3500);
await shot('06-chest');
await load(); await ev(`try{closeWelcome()}catch(e){}`); await sleep(1500);
await ev(`showLeaders()`); await sleep(5000);
await shot('07-leaderboard');
ws.close(); chrome.kill();
