// Shared puzzle lifecycle against the Social Lab's fake server (dev/lab.js), so nothing reaches production (and the harness blocks
// Supabase anyway). Covers the 2026-11-25 reports: start a new shared puzzle right after finishing one, badge sync, claim once,
// a late shared find lighting the badge, and the simultaneous final placing.
// Run from web/: node tools/check-social.mjs
import {startBrowser, checker, sleep} from './lib/browser.mjs';

const b = await startBrowser(), c = checker('check-social');
try {
  await b.go();
  await b.evaluate(`localStorage.setItem('monkeyTrubble.lab','1'),localStorage.removeItem('monkeyTrubble.lab.server'),localStorage.removeItem('monkeyTrubble.lab.save.v1'),localStorage.removeItem('monkeyTrubble.lab.clock')`);
  await b.go();
  const lab = await b.evaluate(`labReady.then(r=>JSON.stringify({LAB,key:SAVE_KEY,ready:!!r}))`).then(JSON.parse);
  c.ok(lab.LAB && lab.ready && lab.key.includes('lab'), 'Social Lab is on with its own save', lab);
  if (!lab.LAB || !lab.ready) throw new Error('lab not on: stopping before any server call');
  await b.evaluate(`(()=>{progress.player={id:crypto.randomUUID(),secret:crypto.randomUUID(),name:'Tester'};Object.assign(progress,{tutorialDone:true,tutorialV:TUTORIAL_VERSION,level:40,mapIntro:true});saveProgress();return syncProfile()})()`);
  const A = a => b.evaluate(`(window.__lab.A.${a}(),window.__labPoke(),1)`).then(() => sleep(400));
  const news = () => b.evaluate(`lbCall('my_news',lbAuth()).then(n=>JSON.stringify(n))`).then(JSON.parse);
  const badge = () => b.evaluate(`(renderPuzzleBadge(),duoNews(newsNow()))`);

  c.section('invite arrives and is accepted mid-session');
  await A('addFriend'); await A('inviteMe');
  c.ok((await news()).duo_invites === 1, 'friend invite shows in news');
  await b.evaluate(`refreshNews(true)`); await sleep(500);
  c.ok(await badge() >= 1, 'puzzle badge counts the invite');
  await b.evaluate(`openPuzzle({mode:'shared'})`); await sleep(900);
  const picking = await b.evaluate(`pz.picking`);
  c.ok(picking, 'invite-only news opens the invite page');
  const accepted = await b.evaluate(`(async()=>{const st=await loadDuo();const v=st.invites[0];const r=await lbCall('duo_answer',{...lbAuth(),p_duo:v.id,p_accept:true});pz.picking=false;pz.duo=v.id;await loadDuo();renderPuzzle();return r+'|'+duo.state.duo.status+'|'+fr.news?.duo_invites})()`);
  c.ok(accepted.startsWith('active|active|0'), 'accept works in-session and the invite count clears', accepted);

  c.section('pieces, last piece, claim once');
  await A('oneLeft');
  const fin = await b.evaluate(`(async()=>{await loadDuo();pz.n=duo.view.key;renderPuzzle();duoPlace(11);duo.view.placed[duo.view.key].push(11);await duo.placing;const bank=JSON.stringify(progress.bank);finishPuzzle(pz.n);await new Promise(r=>setTimeout(r,1200));
    return JSON.stringify({status:duo.state.duo.status,claimed:duo.state.duo.claimed,list:duo.state.duos.map(d=>d.status),bankBefore:bank,bankAfter:JSON.stringify(progress.bank)})})()`).then(JSON.parse);
  c.ok(fin.status === 'done' && fin.claimed === true, 'last piece finishes and the reward is claimed', fin);
  c.ok(fin.list.every(s => s === 'done'), 'finished puzzle leaves the active list without a relaunch', fin.list);
  c.ok(fin.bankBefore !== fin.bankAfter, 'reward reached the bank');
  const dup = await b.evaluate(`lbCall('duo_claim',{...lbAuth(),p_duo:duo.state.duo.id})`);
  c.ok(dup === false, 'a second claim is refused');

  c.section('start another with the same friend');
  const again = await b.evaluate(`(async()=>{renderPuzzle();await new Promise(r=>setTimeout(r,300));const a=[...document.querySelectorAll('#pzTray button')].find(x=>/new shared/i.test(x.textContent));if(!a)return 'no button';a.click();await new Promise(r=>setTimeout(r,900));
    return [...document.querySelectorAll('#pzShared .pzs-row')].map(r=>r.textContent.replace(/\\s+/g,' ').trim()).join(' | ')})()`);
  c.ok(/INVITE/.test(again) && !/BUILDING/.test(again), 'the same friend shows INVITE right away', again);
  const re = await b.evaluate(`(async()=>{const f=fr.home.friends.find(x=>x.id!==progress.player.id);return lbCall('duo_invite',{...lbAuth(),p_friend:f.id,p_art:'together-2'})})()`);
  c.ok(re === 'sent', 're-invite is accepted by the server', re);
  await b.evaluate(`closePuzzle?.()`).catch(() => {});

  c.section('race: both partners place the last two pieces');
  await A('acceptInvites'); await A('twoLeftRace');
  const race = await b.evaluate(`(async()=>{pz.duo=null;await loadDuo();const d=duo.state.duos.find(x=>x.status==='active');pz.duo=d.id;await loadDuo();const loose=duo.state.pieces.find(p=>!p.placed);duoPlace(loose.piece);await duo.placing;return duo.state.duo.status})()`);
  c.ok(race === 'done', 'simultaneous final placing still finishes the puzzle', race);

  c.section('late shared find lights the badge');
  const late = await b.evaluate(`(()=>{duoUnseen=0;const before=duoNews(newsNow());duoUnseen++;renderPuzzleBadge();return duoNews(newsNow())-before})()`);
  c.ok(late === 1, 'an unseen shared find adds 1 to the badge', late);
  const clear = await b.evaluate(`(closePuzzle?.(),openPuzzle({mode:'shared'}),duoUnseen)`);
  c.ok(clear === 0, 'opening shared puzzles clears it', clear);

  c.section('isolation');
  const iso = await b.evaluate(`JSON.stringify({real:localStorage.getItem('monkeyTrubble.save.v1')&&JSON.parse(localStorage.getItem('monkeyTrubble.save.v1')).player?.name||null})`).then(JSON.parse);
  c.ok(iso.real !== 'Tester', 'the real save never got the lab player', iso);
  c.ok(!b.errors.length, 'no page errors', b.errors.slice(0, 3));
} catch (e) { c.ok(false, 'ran without crashing', e.message) }
await b.close();
process.exit(c.end() ? 1 : 0);
