// Puzzle visibility and badge checks (2026-11-26 bug: chapter puzzles 6-11 vanished on the second and later 55-level laps, and
// their unplaced pieces pinned the 🧩 badge). Uses an advanced player's save (level 135, lap 3) with pieces spread around.
// Run from web/: node tools/check-puzzles.mjs
import {startBrowser, checker} from './lib/browser.mjs';

const b = await startBrowser(), c = checker('check-puzzles');
try {
  await b.go();
  const seed = async save => { await b.evaluate(`localStorage.setItem(SAVE_KEY,JSON.stringify(Object.assign(JSON.parse(localStorage.getItem(SAVE_KEY))||freshProgress(),${JSON.stringify(save)})))`); await b.go() };
  const open = () => b.evaluate(`JSON.stringify(puzzlesOpen().map(e=>String(e.key)))`).then(JSON.parse);

  c.section('chapters ever reached');
  const reach = await b.evaluate(`(()=>{const l=progress.level,o={};for(const v of [1,5,6,30,50,55,56,60,110,135,300]){progress.level=v;o[v]=chaptersReached()}progress.level=l;return o})()`);
  c.ok(reach[1] === 1 && reach[6] === 2 && reach[30] === 6 && reach[55] === 11, 'first lap counts chapters up', reach);
  c.ok([56, 60, 110, 135, 300].every(v => reach[v] === 11), 'every later lap has reached all 11 chapters', reach);

  c.section('advanced save (level 135, lap 3)');
  await seed({level: 135, puzzle: {got: {poly: [0,1,2,3,4,5,6,7,8,9,10,11], 1: [0,1,2,3,4,5,6,7,8,9,10,11], 9: [0, 1], 11: [3]}, placed: {poly: [0,1,2,3,4,5,6,7,8,9,10,11], 1: [0,1,2,3,4,5,6,7,8,9,10,11]}, levels: [], done: ['poly', 1], starter: true}});
  const o = await open();
  c.ok(['1','2','3','4','5','6','7','8','9','10','11','11b'].every(k => o.includes(k)), 'all chapter puzzles plus Ice Age II are open', o);
  c.ok(o.includes('11'), 'ICE AGE BATTLE APES (chapter 11) is open');
  const pz = await b.evaluate(`JSON.stringify({got9:puzzleSave().got[9],got11:puzzleSave().got[11],waiting:piecesWaiting()})`).then(JSON.parse);
  c.ok(JSON.stringify(pz.got9) === '[0,1]' && JSON.stringify(pz.got11) === '[3]', 'collected pieces are intact', pz);
  c.ok(pz.waiting === 3, 'badge counts the 3 placeable pieces', pz.waiting);
  const badge = await b.evaluate(`(renderPuzzleBadge(),document.querySelector('#puzzleBadge').textContent)`);
  c.ok(badge === '3', 'home badge shows 3', badge);

  c.section('started puzzles never relock');
  const relock = await b.evaluate(`(()=>{const l=progress.level;progress.level=12;const r=puzzlesOpen().map(e=>String(e.key));progress.level=l;return JSON.stringify(r)})()`).then(JSON.parse);
  c.ok(relock.includes('9') && relock.includes('11'), 'chapter 9/11 puzzles with pieces stay open even at level 12', relock);
  const xmas = await b.evaluate(`(()=>{const p=puzzleSave();p.got['poly-christmas']=[2];const r=puzzlesOpen().some(e=>e.key==='poly-christmas');delete p.got['poly-christmas'];return r})()`);
  c.ok(xmas, 'a started seasonal puzzle stays open out of season');

  c.section('placing clears the badge');
  const after = await b.evaluate(`(()=>{const p=puzzleSave();p.placed[9]=[0,1];p.placed[11]=[3];renderPuzzleBadge();return piecesWaiting()+'|'+document.querySelector('#puzzleBadge').hidden})()`);
  c.ok(after.startsWith('0|') , 'no waiting pieces after placing', after);
  c.ok(!b.errors.length, 'no page errors', b.errors.slice(0, 3));
} catch (e) { c.ok(false, 'ran without crashing', e.message) }
await b.close();
process.exit(c.end() ? 1 : 0);
