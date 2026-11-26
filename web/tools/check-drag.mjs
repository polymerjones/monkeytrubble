// Board drag robustness (2026-11-25 stuck card at level 135: a second finger on a lifted card left a 1.5x drag copy frozen over the
// board) plus booster badge totals. Drives real touch events in headless Chrome on a level-30 board. Every interruption must leave
// no .drag-ghost behind and must never remove a real card; normal play (taps, drag into the cage, two-finger pair, pair clear) must
// still work. Run from web/: node tools/check-drag.mjs
import {startBrowser, checker, sleep} from './lib/browser.mjs';

const b = await startBrowser(), c = checker('check-drag');
const T = (type, pts) => b.touch(type, pts);
const snap = () => b.evaluate(`JSON.stringify({ghosts:document.querySelectorAll('#dragLayer .drag-ghost').length,lifted:document.querySelectorAll('.board-tile.lifted').length,peek:document.body.classList.contains('peek-drag'),active:state.tiles.filter(t=>t.active).length,nodes:document.querySelectorAll('#board .board-tile').length,cage:(state.tray||[]).length})`).then(JSON.parse);
const freeCard = () => b.evaluate(`(()=>{const isFree=t=>t&&t.active&&t.revealed&&![KEVIN,JOKER,POLY].includes(t.symbol)&&!(t.blockers||[]).some(b=>state.tiles.find(x=>x.id===b)?.active);const n=[...document.querySelectorAll('#board .board-tile')].find(n=>{const t=tileOf(n);return isFree(t)&&!n.classList.contains('lifted')&&n.peekBound});if(!n)return 'null';const r=n.getBoundingClientRect();return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2,id:n.dataset.id})})()`).then(JSON.parse);
const drag = async (p, id, dx, dy, steps = 6) => { await T('touchStart', [{x: p.x, y: p.y, id}]); for (let k = 1; k <= steps; k++) { await T('touchMove', [{x: p.x + dx * k / steps, y: p.y + dy * k / steps, id}]); await sleep(25) } };
const clean = (s, what, before) => { c.ok(s.ghosts === 0 && s.lifted === 0 && !s.peek, `${what}: no drag copy left`, s); if (before) c.ok(s.active === before.active && s.nodes === s.active, `${what}: no card lost`, {before: before.active, after: s.active, nodes: s.nodes}) };
try {
  await b.send('Emulation.setTouchEmulationEnabled', {enabled: true, maxTouchPoints: 5});
  await b.go();
  await b.evaluate(`(()=>{const s=JSON.parse(localStorage.getItem(SAVE_KEY))||freshProgress();Object.assign(s,{level:30,tutorialDone:true,tutorialV:TUTORIAL_VERSION,mapIntro:true,bank:{undo:43,shuffle:40,hint:41}});localStorage.setItem(SAVE_KEY,JSON.stringify(s))})()`);
  await b.go();
  await b.evaluate(`(document.querySelectorAll('.show').forEach(e=>e.classList.remove('show')),document.querySelector('#homePlay').click(),1)`); await sleep(1500);
  await b.evaluate(`(document.querySelectorAll('.dialog.show').forEach(e=>e.classList.remove('show')),1)`); await sleep(3000);
  c.ok(await b.evaluate(`document.querySelector('#home').classList.contains('hidden')&&state.tiles.length>20`), 'a real level is on screen');

  c.section('booster badges = free + banked');
  const badges = () => b.evaluate(`['undo','shuffle','hint'].map(k=>document.querySelector('#'+k+'Count').textContent).join(' ')`);
  const exp = await b.evaluate(`[state.undosLeft+progress.bank.undo,state.shufflesLeft+progress.bank.shuffle,state.hintsLeft+progress.bank.hint].join(' ')`);
  c.ok(await badges() === exp, 'level start shows the totals', {shown: await badges(), exp});

  c.section('interrupted drags');
  let p = await freeCard(), before = await snap();
  await drag(p, 1, 48, 60); await T('touchStart', [{x: p.x + 48, y: p.y + 60, id: 1}, {x: p.x, y: p.y, id: 2}]); await sleep(60);
  for (let k = 1; k <= 6; k++) { await T('touchMove', [{x: p.x + 48 + k * 4, y: p.y + 60 + k * 4, id: 1}, {x: p.x - k * 8, y: p.y + k * 8, id: 2}]); await sleep(30) }
  await T('touchEnd', [{x: p.x, y: p.y, id: 2}]); await T('touchEnd', []); await sleep(1800);
  clean(await snap(), 'second finger on a lifted card', before);
  for (const [what, js] of [['app hidden mid-drag', `Object.defineProperty(document,'hidden',{configurable:true,get:()=>true}),document.dispatchEvent(new Event('visibilitychange')),delete document.hidden`],
    ['Notification Center (blur) mid-drag', `dispatchEvent(new Event('blur'))`], ['pagehide mid-drag', `dispatchEvent(new Event('pagehide'))`], ['rotation mid-drag', `cancelDragForRotate()`]]) {
    p = await freeCard(); before = await snap(); await drag(p, 3, 40, -50);
    const mid = await snap(); c.ok(mid.ghosts === 1, `${what}: drag was live`, mid);
    await b.evaluate(`(${js},1)`); await sleep(1800); await T('touchCancel', []); await sleep(300);
    clean(await snap(), what, before);
  }
  p = await freeCard(); before = await snap(); await drag(p, 4, -40, -30);
  await b.evaluate(`(openPuzzle(),1)`); await sleep(1500); await b.evaluate(`(closePuzzle(),1)`); await T('touchCancel', []); await sleep(800);
  clean(await snap(), 'puzzles opened mid-drag', before);
  p = await freeCard(); before = await snap();
  for (let r = 0; r < 6; r++) { await T('touchStart', [{x: p.x, y: p.y, id: 10 + r}]); for (let k = 1; k <= 4; k++) { await T('touchMove', [{x: p.x + k * 6, y: p.y + k * 6, id: 10 + r}]); await sleep(16) } await T('touchEnd', []); await sleep(30) }
  await sleep(1800); clean(await snap(), 'rapid repeated drags', before);

  c.section('normal play still works');
  const pair = await b.evaluate(`(()=>{const isFree=t=>t&&t.active&&t.revealed&&![KEVIN,JOKER,POLY].includes(t.symbol)&&!(t.blockers||[]).some(b=>state.tiles.find(x=>x.id===b)?.active);const f=[...document.querySelectorAll('#board .board-tile')].map(n=>tileOf(n)).filter(isFree);const by={};for(const t of f)(by[t.symbol]??=[]).push(t.id);return JSON.stringify(Object.values(by).find(a=>a.length>=2)||null)})()`).then(JSON.parse);
  if (pair) { const pos = id => b.evaluate(`(()=>{const r=document.querySelector('#board [data-id="${id}"]').getBoundingClientRect();return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2})})()`).then(JSON.parse);
    const a1 = await pos(pair[0]), a2 = await pos(pair[1]); before = await snap();
    await T('touchStart', [{x: a1.x, y: a1.y, id: 20}, {x: a2.x, y: a2.y, id: 21}]); await sleep(80); await T('touchEnd', []); await sleep(2500);
    const s = await snap(); c.ok(s.active === before.active - 2, 'two-finger pair clears the pair', {before: before.active, after: s.active}) }
  else c.ok(true, 'two-finger pair (no free pair on this board, skipped)');
  before = await snap(); p = await freeCard(); await T('touchStart', [{x: p.x, y: p.y, id: 30}]); await sleep(60); await T('touchEnd', []); await sleep(1500);
  let s = await snap(); c.ok(s.active === before.active - 1 && s.cage === before.cage + 1, 'a tap sends the card to the cage', {before, s});
  before = s; p = await freeCard();
  const tr = await b.evaluate(`(()=>{const r=document.querySelector('#tray, .tray').getBoundingClientRect();return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2})})()`).then(JSON.parse);
  await drag(p, 31, tr.x - p.x, tr.y - p.y, 12); await T('touchEnd', []); await sleep(2000);
  s = await snap(); c.ok(s.active === before.active - 1 && s.cage === before.cage + 1 && s.ghosts === 0, 'dragging a card into the cage plays it', {before, s});
  // A match in the cage: tap a free card whose symbol is already caged (or any two of a kind).
  before = s;
  const mate = await b.evaluate(`(()=>{const isFree=t=>t&&t.active&&t.revealed&&![KEVIN,JOKER,POLY].includes(t.symbol)&&!(t.blockers||[]).some(b=>state.tiles.find(x=>x.id===b)?.active);const caged=new Set((state.tray||[]).map(x=>x.symbol));const n=[...document.querySelectorAll('#board .board-tile')].find(n=>{const t=tileOf(n);return isFree(t)&&caged.has(t.symbol)});if(!n)return 'null';const r=n.getBoundingClientRect();return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2})})()`).then(JSON.parse);
  if (mate) { await T('touchStart', [{x: mate.x, y: mate.y, id: 40}]); await sleep(60); await T('touchEnd', []); await sleep(2200); s = await snap(); c.ok(s.cage === before.cage - 1 && s.active === before.active - 1, 'a caged match clears the pair', {before, s}) }
  else c.ok(true, 'caged match (no matching free card on this board, skipped)');

  c.section('boosters after play, home and back');
  const exp2 = await b.evaluate(`[state.undosLeft+progress.bank.undo,state.shufflesLeft+progress.bank.shuffle,state.hintsLeft+progress.bank.hint].join(' ')`);
  c.ok(await badges() === exp2, 'mid-level totals', {shown: await badges(), exp: exp2});
  await b.evaluate(`(showHome(),1)`); await sleep(800); await b.evaluate(`(document.querySelector('#homePlay').click(),1)`); await sleep(2500);
  const exp3 = await b.evaluate(`[state.undosLeft+progress.bank.undo,state.shufflesLeft+progress.bank.shuffle,state.hintsLeft+progress.bank.hint].join(' ')`);
  c.ok(await badges() === exp3, 'after home and back', {shown: await badges(), exp: exp3});
  c.ok(!b.errors.length, 'no page errors', b.errors.slice(0, 3));
} catch (e) { c.ok(false, 'ran without crashing', e.message) }
await b.close();
process.exit(c.end() ? 1 : 0);
