// Streak milestone chests (1.1.3): 14/30/60/100 days, paid once, retroactive for players already past them, never twice across
// devices (progress.milestones merges as a union). Fresh temp profile; Supabase is blocked by the harness.
// Run from web/: node tools/check-streak.mjs
import {startBrowser, checker, sleep} from './lib/browser.mjs';

const b = await startBrowser(), c = checker('check-streak');
try {
  await b.go();
  await b.evaluate(`(progress.bank={undo:5,shuffle:5,hint:5},progress.milestones=[],saveProgress(),1)`);

  c.section('which milestones are due');
  const due = await b.evaluate(`JSON.stringify([13,14,29,30,45,100].map(n=>milestonesDue(n).map(m=>m.days)))`).then(JSON.parse);
  c.ok(JSON.stringify(due) === JSON.stringify([[], [14], [14], [14, 30], [14, 30], [14, 30, 60, 100]]), 'due lists', due);
  const plain = await b.evaluate(`JSON.stringify(chestDue({firstToday:true,streak:7,level:40}))`).then(JSON.parse);
  c.ok(plain?.big && !plain.milestones, 'day 7 is still the usual big chest', plain);

  c.section('an existing 31-day player gets 14 and 30 at once');
  const d = await b.evaluate(`JSON.stringify(chestDue({firstToday:true,streak:31,level:40}))`).then(JSON.parse);
  c.ok(d?.milestones?.map(m => m.days).join() === '14,30', 'retroactive milestones offered', d);
  const before = await b.evaluate(`JSON.stringify(progress.bank)`).then(JSON.parse);
  await b.evaluate(`(window.__ms=playChestScene(${JSON.stringify(d)}),1)`); await sleep(1500);
  const kicker = await b.evaluate(`document.querySelector('#csKicker').textContent`);
  c.ok(/30-DAY STREAK MILESTONE/.test(kicker), 'chest says it is the milestone', kicker);
  for (let i = 0; i < 8 && !(await b.evaluate(`!!document.querySelector('#csActions .cs-collect')`)); i++) { await b.evaluate(`document.querySelector('#chestScene').dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}))`); await sleep(500) }
  await sleep(1500);
  await b.evaluate(`document.querySelector('#csActions .cs-collect')?.click()`); await sleep(1500);
  const after = await b.evaluate(`JSON.stringify({bank:progress.bank,ms:progress.milestones})`).then(JSON.parse);
  const gained = ['undo', 'shuffle', 'hint'].map(k => after.bank[k] - before[k]);
  c.ok(after.ms.join() === '14,30', 'milestones recorded on collect', after.ms);
  c.ok(gained.every(g => g >= 1) && gained.reduce((a, x) => a + x, 0) >= 5, 'big chest + 1 of each booster landed in the bank', gained);
  const again = await b.evaluate(`JSON.stringify(chestDue({firstToday:true,streak:32,level:40}))`).then(JSON.parse);
  c.ok(!again?.milestones, 'not offered again the next day', again);

  c.section('two devices');
  const merged = await b.evaluate(`JSON.stringify(mergeSaves({...progress,milestones:[14],stats:{...progress.stats,xp:999999}},{...progress,milestones:[30,60]}).milestones.sort((a,b)=>a-b))`).then(JSON.parse);
  c.ok(merged.join() === '14,30,60', 'milestones merge as a union (never paid twice)', merged);
  const line = await b.evaluate(`(progress.milestones=[14,30],streakSceneLine(58))`);
  c.ok(/60-day milestone/.test(line), 'streak scene counts down to the next milestone', line);
  c.ok(!b.errors.length, 'no page errors', b.errors.slice(0, 3));
} catch (e) { c.ok(false, 'ran without crashing', e.message) }
await b.close();
process.exit(c.end() ? 1 : 0);
