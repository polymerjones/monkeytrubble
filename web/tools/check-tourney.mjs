// Troop Tournaments end to end in the Social Lab (fake server, time warp; Supabase blocked by the harness): create with friends,
// friends join and play, your levels and puzzles score once (re-sent syncs don't double), an incoming invite needs JOIN, warp to
// the deadline, results freeze, claim once with the reward, celebration. Saves screenshots to $SHOTS if set.
// Run from web/: node tools/check-tourney.mjs      (SHOTS=/some/dir to keep screenshots)
import {startBrowser, checker, sleep} from './lib/browser.mjs';
import {writeFileSync} from 'node:fs';

const b = await startBrowser(), c = checker('check-tourney'), SHOTS = process.env.SHOTS;
const shot = async name => { if (!SHOTS) return; const r = await b.send('Page.captureScreenshot', {format: 'png'}); writeFileSync(`${SHOTS}/${name}.png`, Buffer.from(r.data, 'base64')) };
try {
  await b.send('Emulation.setDeviceMetricsOverride', {width: 430, height: 932, deviceScaleFactor: 2, mobile: true});
  await b.go();
  await b.evaluate(`localStorage.setItem('monkeyTrubble.lab','1'),['monkeyTrubble.lab.server','monkeyTrubble.lab.save.v1','monkeyTrubble.lab.clock'].forEach(k=>localStorage.removeItem(k))`);
  await b.go();
  const on = await b.evaluate(`labReady.then(r=>!!r&&LAB)`);
  c.ok(on, 'Social Lab is on'); if (!on) throw new Error('lab not on: stopping');
  await b.evaluate(`(()=>{progress.player={id:crypto.randomUUID(),secret:crypto.randomUUID(),name:'Paul'};Object.assign(progress,{tutorialDone:true,tutorialV:TUTORIAL_VERSION,level:40,mapIntro:true,bank:{undo:10,shuffle:10,hint:10}});saveProgress();return syncProfile()})()`);
  const A = a => b.evaluate(`(window.__lab.A.${a}(),window.__labPoke(),1)`).then(() => sleep(500));
  await A('addFriend'); await A('addFriend'); await A('addFriend');
  await b.evaluate(`(document.querySelectorAll('.overlay.show').forEach(e=>e.classList.remove('show')),showHome?.(),renderHome(),1)`); await sleep(800);
  c.ok(await b.evaluate(`document.querySelector('#homeTourney').hidden`), 'no chip before any tournament');

  c.section('create');
  await b.evaluate(`(openTourney(),1)`); await sleep(800); await shot('1-intro');
  await b.evaluate(`[...document.querySelectorAll('#tourneyBody button')].find(x=>/START ONE/.test(x.textContent)).click()`); await sleep(900);
  const boxes = await b.evaluate(`document.querySelectorAll('#tourneyBody input[type=checkbox]').length`);
  c.ok(boxes === 3, 'friend picker lists the 3 friends', boxes);
  await b.evaluate(`(()=>{const cbs=[...document.querySelectorAll('#tourneyBody input[type=checkbox]')];cbs[0].click();cbs[1].click();return 1})()`); await shot('2-picker');
  await b.evaluate(`[...document.querySelectorAll('#tourneyBody button')].find(x=>/START THE TOURNAMENT/.test(x.textContent)).click()`); await sleep(1200);
  let st = await b.evaluate(`JSON.stringify(tourneyNow())`).then(JSON.parse);
  c.ok(st?.status === 'live' && st.my_status === 'joined' && st.standings.length === 1 && st.invited.length === 2, 'tournament is live: you joined, 2 invited', st && {s: st.status, m: st.my_status, n: st.standings.length, i: st.invited?.length});
  c.ok(Date.parse(st.ends_at) - Date.parse(st.starts_at) === 5 * 864e5, 'runs exactly 5 days');

  c.section('friends join, everyone plays');
  await A('botsJoin'); await A('botsPlay');
  await b.evaluate(`(()=>{progress.level+=3;const p=puzzleSave();p.placed.poly=[...new Set([...(p.placed.poly||[]),0,1,2,3,4,5,6,7,8,9,10,11])];if(!p.done.includes('poly'))p.done.push('poly');saveProgress();return syncProfile()})()`); await sleep(900);
  st = await b.evaluate(`refreshTourneys(true).then(()=>JSON.stringify(tourneyNow()))`).then(JSON.parse);
  const me = st.standings.find(x => x.me);
  c.ok(st.standings.length === 3, 'both friends joined', st.standings.length);
  c.ok(me.levels === 3 && me.points === 30 + me.pieces * 3 + me.puzzles * 25, 'your new levels and puzzles score', me);
  await b.evaluate(`syncProfile()`); await b.evaluate(`syncProfile()`); await sleep(600);
  const me2 = await b.evaluate(`refreshTourneys(true).then(()=>JSON.stringify(tourneyNow().standings.find(x=>x.me)))`).then(JSON.parse);
  c.ok(me2.points === me.points, 're-sent syncs do not count twice', {before: me.points, after: me2.points});
  await b.evaluate(`(progress.level=Math.max(1,progress.level-2),saveProgress(),syncProfile())`); await sleep(500);
  const me3 = await b.evaluate(`refreshTourneys(true).then(()=>JSON.stringify(tourneyNow().standings.find(x=>x.me)))`).then(JSON.parse);
  c.ok(me3.points === me.points, 'replaying older levels adds nothing', me3.points);
  await b.evaluate(`(openTourney(),1)`); await sleep(900); await shot('3-standings');
  await b.evaluate(`(closeTourney(),renderHome(),1)`); await sleep(600);
  const chip = await b.evaluate(`document.querySelector('#homeTourney').hidden?'hidden':document.querySelector('#homeTourney').textContent`);
  c.ok(/of 3/.test(chip) && /LEFT/.test(chip), 'home chip shows place and countdown', chip); await shot('4-home-chip');

  c.section('an invite from a friend needs JOIN');
  await A('tourneyInviteMe'); await sleep(400);
  st = await b.evaluate(`refreshTourneys(true).then(()=>JSON.stringify(tourneyNow()))`).then(JSON.parse);
  c.ok(st.my_status === 'invited', 'the invite shows first, not auto-joined', st.my_status);
  const n = await b.evaluate(`lbCall('my_news',lbAuth()).then(n=>JSON.stringify(n.tourney))`).then(JSON.parse);
  c.ok(n?.invites === 1, 'news carries the tournament invite', n);
  await b.evaluate(`(openTourney(),1)`); await sleep(700); await shot('5-invite');
  await b.evaluate(`[...document.querySelectorAll('#tourneyBody button')].find(x=>/JOIN THE TOURNAMENT/.test(x.textContent)).click()`); await sleep(1200);
  st = await b.evaluate(`JSON.stringify(tr.state.tourneys.find(t=>t.host.name!=='Paul'))`).then(JSON.parse);
  c.ok(st.my_status === 'joined', 'JOIN joins');
  await b.evaluate(`(closeTourney(),1)`);

  c.section('time warp to the end, claim once');
  await b.evaluate(`(window.__lab.warp(5*864e5+120e3),window.__labPoke(),1)`); await sleep(900);
  await b.evaluate(`(progress.level+=5,saveProgress(),syncProfile())`); await sleep(700);
  const mine = await b.evaluate(`refreshTourneys(true).then(()=>JSON.stringify(tr.state.tourneys.find(t=>t.host.name==='Paul')))`).then(JSON.parse);
  c.ok(mine.status === 'finished', 'deadline passed: finished');
  c.ok(mine.standings.find(x => x.me).points === me.points, 'levels after the deadline do not count', mine.standings.find(x => x.me).points);
  await b.evaluate(`(renderHome(),1)`); await sleep(500);
  const chip2 = await b.evaluate(`document.querySelector('#homeTourney').textContent`);
  c.ok(/over/i.test(chip2), 'home chip says it is over', chip2);
  const bank0 = await b.evaluate(`JSON.stringify(progress.bank)`).then(JSON.parse);
  await b.evaluate(`(openTourney(${mine.id}),1)`); await sleep(800);
  await b.evaluate(`[...document.querySelectorAll('#tourneyBody button')].find(x=>/SEE WHO WON/.test(x.textContent)).click()`); await sleep(1500); await shot('6-celebration');
  const cel = await b.evaluate(`document.querySelector('#tourneyBody .t-win')?.textContent||''`);
  c.ok(/WON|finished/.test(cel), 'celebration shows the result', cel);
  const bank1 = await b.evaluate(`JSON.stringify(progress.bank)`).then(JSON.parse);
  c.ok(bank1.undo > bank0.undo, 'reward landed in the bank', {bank0, bank1});
  const dup = await b.evaluate(`lbCall('tourney_claim',{...lbAuth(),p_tourney:${mine.id}}).then(r=>JSON.stringify(r))`).then(JSON.parse);
  c.ok(dup.ok === false, 'a second claim is refused');

  c.section('ties share first');
  await b.evaluate(`(window.__lab.resetClock(),1)`);
  await b.evaluate(`(document.querySelectorAll('.overlay.show').forEach(e=>e.classList.remove('show')),1)`);
  const tie = await b.evaluate(`(async()=>{const f=fr.home?.friends?.filter(x=>x.id!==progress.player.id).map(x=>x.id)||(await fetchFriendsHome()).friends.filter(x=>x.id!==progress.player.id).map(x=>x.id);
    const r=await lbCall('tourney_create',{...lbAuth(),p_friends:f.slice(0,1),p_name:'Tie'});window.__lab.A.botsJoin();const st=await lbCall('tourney_state',lbAuth());const t=st.tourneys.find(x=>x.id===r.id);return JSON.stringify(t.standings.map(s=>s.place))})()`).then(JSON.parse);
  c.ok(tie.length === 2 && tie.every(p => p === 1), 'equal points share 1st place', tie);
  c.ok(!b.errors.length, 'no page errors', b.errors.slice(0, 3));
} catch (e) { c.ok(false, 'ran without crashing', e.message) }
await b.close();
process.exit(c.end() ? 1 : 0);
