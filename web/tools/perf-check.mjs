// Performance regression check for index.html (Apple's XCTest `measure` idea, Paul 2026-10-29), using the page's own signposts
// (perf.begin/end → perf.log):
// - serves web/ on localhost and drives a fresh headless Chrome (phone-sized, CPU throttled 6×, like the earlier perf passes);
// - each run loads the game, then for every scenario jumps to the level (dev GO), waits for it to settle and wins it (dev INSTANT WIN);
// - records each signpost's time (startLevel, levelTransition, winScore, preloadAssets...) and the frames slower than 34ms;
// - takes the median of RUNS runs and compares it to tools/perf-baseline.json: a time that is more than 25% and 20ms slower, or
//   3+ extra slow frames, fails (exit 1).
// Headless Chrome can't show GPU costs (filters, big layers); the FPS meter and hang detector on the phone are the judge for those.
// Run: node tools/perf-check.mjs            (compare with the baseline)
//      node tools/perf-check.mjs --update   (save this machine's numbers as the new baseline)
import {createServer} from 'node:http';
import {readFile, writeFile, mkdtemp, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join, extname, normalize} from 'node:path';
import {fileURLToPath} from 'node:url';

const ROOT=fileURLToPath(new URL('..',import.meta.url)),BASELINE=join(ROOT,'tools/perf-baseline.json');
const CHROME=process.env.CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const RUNS=3,THROTTLE=6,SLOW_FRAME_MS=34;
// Level 22 is the board the earlier perf passes used; 51 is the first Expedition+ level.
const SCENARIOS=[{level:1},{level:22},{level:22,pack:'halloween'},{level:51}];
const update=process.argv.includes('--update');

const TYPES={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp','.gif':'image/gif','.mp3':'audio/mpeg','.m4a':'audio/mp4','.ogg':'audio/ogg','.wav':'audio/wav','.woff2':'font/woff2','.woff':'font/woff','.ttf':'font/ttf','.webmanifest':'application/manifest+json'};
const server=createServer(async(req,res)=>{const path=normalize(decodeURIComponent(new URL(req.url,'http://x').pathname)).replace(/^(\.\.[/\\])+/,'');
  try{const body=await readFile(join(ROOT,path==='/'?'index.html':path));res.writeHead(200,{'content-type':TYPES[extname(path).toLowerCase()]||'application/octet-stream'});res.end(body)}catch{res.writeHead(404);res.end()}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin=`http://127.0.0.1:${server.address().port}`;

const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const median=a=>{const s=[...a].sort((x,y)=>x-y),m=s.length>>1;return s.length%2?s[m]:(s[m-1]+s[m])/2};

// One fresh Chrome per run (its own profile dir, removed after), so no saved progress or cache leaks between runs.
async function runOnce(){
  const profile=await mkdtemp(join(tmpdir(),'mt-perf-'));
  const chrome=spawn(CHROME,['--headless=new','--remote-debugging-port=0',`--user-data-dir=${profile}`,'--window-size=430,932','--no-first-run','--no-default-browser-check','--mute-audio','--autoplay-policy=no-user-gesture-required','about:blank'],{stdio:['ignore','ignore','pipe']});
  try{
    const browserWs=await new Promise((resolve,reject)=>{let buf='';const t=setTimeout(()=>reject(new Error('Chrome did not start')),15000);
      chrome.stderr.on('data',d=>{buf+=d;const m=buf.match(/DevTools listening on (ws:\/\/\S+)/);if(m){clearTimeout(t);resolve(m[1])}})});
    const port=new URL(browserWs).port,page=(await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t=>t.type==='page');
    const ws=new WebSocket(page.webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
    let seq=0;const pending=new Map(),events=[];
    ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id&&pending.has(m.id)){const{resolve,reject}=pending.get(m.id);pending.delete(m.id);m.error?reject(new Error(m.error.message)):resolve(m.result)}else if(m.method)events.push(m)};
    const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))});
    const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value};
    const until=async(expression,timeout,what)=>{const end=Date.now()+timeout;while(Date.now()<end){if(await evaluate(expression).catch(()=>false))return;await sleep(100)}throw new Error(`timed out waiting for ${what}`)};

    await send('Page.enable');await send('Runtime.enable');
    // Emulation only after navigating: before it, the page's frame redirect sees a desktop window.
    await send('Page.navigate',{url:`${origin}/index.html?dev&noframe`});
    await until(`document.querySelector('#assetLoader')?.classList.contains('ready')`,60000,'the loader (CAGE READY)');
    await send('Emulation.setCPUThrottlingRate',{rate:THROTTLE});
    await sleep(1500);
    const results={};const add=(k,v)=>{(results[k]??=[]).push(v)};
    for(const e of await evaluate(`perf.log.filter(e=>e.name==='preloadAssets')`))add('launch preloadAssets',e.ms);
    for(const sc of SCENARIOS){const key=`L${sc.level}${sc.pack?' '+sc.pack:''}`;
      // A frame recorder for this scenario: every rAF gap over SLOW_FRAME_MS, from the jump until the win screen is done.
      await evaluate(`(()=>{perf.log.length=0;${sc.pack?`trials.pack=${JSON.stringify(sc.pack)};applyTrials();`:`trials.pack=TRIAL_DEFAULTS.pack;applyTrials();`}
        const f=window.__mtFrames={slow:0,stop:false};let last=performance.now();const tick=now=>{if(now-last>${SLOW_FRAME_MS})f.slow++;last=now;if(!f.stop)requestAnimationFrame(tick)};requestAnimationFrame(tick)})()`);
      await evaluate(`devGoTo(${sc.level})`);
      await until(`state.level===${sc.level}&&!perf.open.size&&!ex.busy&&!levelTransitioning`,30000,`level ${sc.level} to start`);
      await sleep(1500);
      await evaluate(`devInstantWin()`);
      await until(`state.won&&perf.log.some(e=>e.name==='winScore')&&!perf.open.size`,45000,`level ${sc.level}'s win screen`);
      const {log,slow}=await evaluate(`(()=>{__mtFrames.stop=true;return{log:perf.log,slow:__mtFrames.slow}})()`);
      const sums={};for(const e of log)sums[e.name]=(sums[e.name]||0)+e.ms;
      for(const[name,ms]of Object.entries(sums))add(`${key} ${name}`,Math.round(ms));
      add(`${key} slow frames`,slow);
      await evaluate(`showHome()`);await sleep(600)}
    ws.close();return results}
  finally{chrome.kill();await sleep(300);await rm(profile,{recursive:true,force:true}).catch(()=>{})}}

const runs=[];
for(let i=0;i<RUNS;i++){process.stdout.write(`run ${i+1}/${RUNS}… `);runs.push(await runOnce());console.log('ok')}
server.close();
const keys=[...new Set(runs.flatMap(r=>Object.keys(r)))].sort();
const now=Object.fromEntries(keys.map(k=>[k,median(runs.flatMap(r=>r[k]??[]))]));

if(update||!existsSync(BASELINE)){
  await writeFile(BASELINE,JSON.stringify({saved:new Date().toISOString(),machine:`${process.platform} ${process.arch}`,throttle:THROTTLE,runs:RUNS,metrics:now},null,1)+'\n');
  for(const k of keys)console.log(`${k.padEnd(40)} ${String(now[k]).padStart(7)}`);
  console.log(`\nBaseline saved to tools/perf-baseline.json`);process.exit(0)}

const base=JSON.parse(await readFile(BASELINE,'utf8')).metrics,problems=[];
console.log(`${'measure'.padEnd(40)} ${'base'.padStart(7)} ${'now'.padStart(7)}`);
for(const k of keys){const b=base[k],n=now[k],frames=k.endsWith('slow frames');
  const bad=b!=null&&(frames?n-b>=3:n>b*1.25&&n-b>20);if(bad)problems.push(`${k}: ${b} → ${n}${frames?'':'ms'}`);
  console.log(`${k.padEnd(40)} ${String(b??'—').padStart(7)} ${String(n).padStart(7)}${bad?'  ✗ SLOWER':''}`)}
if(problems.length){console.log(`\n${problems.length} regression(s):\n  ${problems.join('\n  ')}`);process.exit(1)}
console.log('\nNo regressions.');
