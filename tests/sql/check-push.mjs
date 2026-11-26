// Push notification server side (2026-11-26-push.sql) on real Postgres (PGlite) over the production schema + the 1.1.3 migrations.
// Run: node tests/sql/check-push.mjs   (setup: cd tests/sql && npm install)
import {fresh} from './load-schema.mjs';
import {readFileSync} from 'node:fs';
const M=new URL('../../web/supabase/migrations/', import.meta.url).pathname, mig=f=>readFileSync(M+f,'utf8');
let fails=0;const ok=(c,w,d)=>{console.log(`  ${c?'PASS':'FAIL'} ${w}${!c&&d!==undefined?' '+JSON.stringify(d):''}`);if(!c)fails++};
async function setup(order){const db=await fresh();for(const f of order)await db.exec(mig(f));return db}
const ALL=['2026-11-26-duo-place-lock.sql','2026-11-26-tournaments.sql','2026-11-26-push.sql'];

console.log('applies');
for(const order of [ALL,['2026-11-26-duo-place-lock.sql','2026-11-26-push.sql']]){try{await setup(order);ok(true,`applies: ${order.map(f=>f.slice(11,-4)).join(' + ')}`)}catch(e){ok(false,'applies',e.message)}}
const db=await setup(ALL);await db.exec(mig('2026-11-26-push.sql'));ok(true,'safe to run twice');
const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p)=>(await q(s,p))[0];
const P={};for(const n of ['Paul','Kaulin','Sam']){const id=crypto.randomUUID(),sec=`secret-secret-${n}-xyz`;P[n.toLowerCase()]={id,sec};await q(`select * from submit_score($1,$2,$3,100,1000,3,40)`,[id,sec,n])}
const fr=async(a,b)=>{const code=(await one(`select friends_home($1,$2) j`,[P[b].id,P[b].sec])).j.code;await q(`select add_friend($1,$2,$3)`,[P[a].id,P[a].sec,code]);await q(`select answer_friend($1,$2,$3,true)`,[P[b].id,P[b].sec,P[a].id])};
const tok=(n,i)=>`tok-${n}-${i}-`+'x'.repeat(40);
const out=async player=>q(`select kind,msg,args,dedupe,due_at>now() as later from push_outbox where player=$1 order by id`,[player]);

console.log('devices');
await fr('paul','kaulin');
ok((await out(P.kaulin.id)).length===0,'no device: nothing queued (friend request/accept happened)');
for(let i=0;i<12;i++)await q(`select register_device($1,$2,'ios',$3,'sandbox','es',-300,'1.1.4')`,[P.kaulin.id,P.kaulin.sec,tok('k',i)]);
await q(`select register_device($1,$2,'android',$3)`,[P.paul.id,P.paul.sec,tok('p',0)]);await q(`select register_device($1,$2,'ios',$3)`,[P.paul.id,P.paul.sec,tok('p',1)]);
ok((await one(`select count(*)::int n from device_tokens where player=$1`,[P.kaulin.id])).n===10,'at most 10 devices per player (oldest dropped)');
await q(`select register_device($1,$2,'ios',$3)`,[P.sam.id,P.sam.sec,tok('k',11)]);
ok((await one(`select player from device_tokens where token=$1`,[tok('k',11)])).player===P.sam.id,'a token moving to another player moves its row');
await q(`select unregister_device($1,$2,$3)`,[P.sam.id,P.sam.sec,tok('k',11)]);
ok(!(await one(`select 1 x from device_tokens where token=$1`,[tok('k',11)])),'unregister removes the device');

console.log('events queue once');
await q(`select duo_invite($1,$2,$3,'together-1')`,[P.paul.id,P.paul.sec,P.kaulin.id]);
let k=await out(P.kaulin.id);ok(k.length===1&&k[0].msg==='duoInvite'&&k[0].args[0]==='Paul','shared puzzle invite → push to invitee with inviter name',k);
const duo=(await one(`select id from duo_puzzles where a=$1`,[P.paul.id])).id;
await q(`select duo_answer($1,$2,$3,true)`,[P.kaulin.id,P.kaulin.sec,duo]);
let p=await out(P.paul.id);ok(p.length===1&&p[0].msg==='duoAccepted','accept → push to inviter',p);
for(let g=0;g<12;g++)await q(`insert into duo_pieces(duo,piece,found_by,found_level) values($1,$2,$3,$4)`,[duo,g,P.paul.id,g+1]);
for(let g=0;g<12;g++)await q(`select duo_place($1,$2,$3,$4)`,[P.paul.id,P.paul.sec,duo,g]);
ok((await out(P.paul.id)).some(r=>r.msg==='duoDone')&&(await out(P.kaulin.id)).some(r=>r.msg==='duoDone'),'finished → push to both');
await q(`update players set last_played=now()-interval '2 days' where id=$1`,[P.kaulin.id]);await q(`select nudge($1,$2,$3,3)`,[P.paul.id,P.paul.sec,P.kaulin.id]);
ok((await out(P.kaulin.id)).some(r=>r.msg==='nudge'&&r.args[1]===3),'nudge → push with the line number');
const before=(await out(P.kaulin.id)).length;await q(`select push_enqueue($1,'duo','duoInvite','[]'::jsonb,$2)`,[P.kaulin.id,`duo-invite:${duo}`]);
ok((await out(P.kaulin.id)).length===before,'same event can never be queued twice (dedupe)');

console.log('claim, send, retry, dead tokens');
await q(`set role service_role`);
let c=(await one(`select push_claim(100) j`)).j;
ok(c.length>=5,'claim returns due pushes',c.length);
const kc=c.find(r=>r.player===P.kaulin.id&&r.msg==='duoInvite');ok(kc.devices.length===9&&kc.devices[0].lang==='es','each push lists all of the player\'s devices with language',kc.devices.length);
ok((await one(`select push_claim(100) j`)).j.length===0,'a second sender at the same time gets nothing (lease)');
// Paul's duoAccepted: android sent, ios transient failure
const pc=c.find(r=>r.player===P.paul.id&&r.msg==='duoAccepted');
await q(`select push_report($1::json)`,[JSON.stringify([{id:pc.id,token:tok('p',0),result:'sent'},{id:pc.id,token:tok('p',1),result:'retry',detail:'503',retry_in_s:30}])]);
// Kaulin's invite: one dead token, rest sent
await q(`select push_report($1::json)`,[JSON.stringify(kc.devices.map((d,i)=>({id:kc.id,token:d.token,result:i===0?'dead':'sent'})))]);
// everything else: sent
const rest=c.filter(r=>r!==pc&&r!==kc);await q(`select push_report($1::json)`,[JSON.stringify(rest.flatMap(r=>r.devices.map(d=>({id:r.id,token:d.token,result:'sent'}))))]);await q(`reset role`);
ok((await one(`select count(*)::int n from device_tokens where player=$1`,[P.kaulin.id])).n===8,'dead token deleted');
ok((await one(`select done_at is not null d from push_outbox where id=$1`,[kc.id])).d,'push done once every remaining device has it');
ok((await one(`select done_at is null d from push_outbox where id=$1`,[pc.id])).d,'partly failed push stays queued');
await q(`update push_outbox set due_at=now()-interval '1 s' where id=$1`,[pc.id]);await q(`set role service_role`);
c=(await one(`select push_claim(100) j`)).j;const again=c.find(r=>r.id===pc.id);
ok(again&&again.devices.length===1&&again.devices[0].token===tok('p',1),'retry only goes to the device that missed it',again?.devices);
await q(`select push_report($1::json)`,[JSON.stringify([{id:pc.id,token:tok('p',1),result:'sent'}])]);await q(`reset role`);
ok((await one(`select done_at is not null d from push_outbox where id=$1`,[pc.id])).d,'then it is done');
// give up after 6 attempts
await q(`insert into push_outbox(player,kind,msg,dedupe,attempts) values($1,'friend','request','t-giveup',5)`,[P.paul.id]);await q(`set role service_role`);
c=(await one(`select push_claim(100) j`)).j;const gu=c.find(r=>r.msg==='request');
await q(`select push_report($1::json)`,[JSON.stringify(gu.devices.map(d=>({id:gu.id,token:d.token,result:'retry',retry_in_s:30})))]);await q(`reset role`);
const g=await one(`select done_at is not null d,last_error from push_outbox where id=$1`,[gu.id]);ok(g.d&&/gave up/.test(g.last_error),'gives up after 6 attempts, with a reason',g);
// player with no devices left: claim + empty report finishes it
await q(`insert into push_outbox(player,kind,msg,dedupe) values($1,'friend','request','t-nodev')`,[P.sam.id]);await q(`set role service_role`);
c=(await one(`select push_claim(100) j`)).j;await q(`select push_report('[]'::json)`);await q(`reset role`);
ok((await one(`select done_at is not null d from push_outbox where dedupe='t-nodev'`)).d,'no devices left: finished, not stuck');

console.log('daily cap and quiet');
for(let i=0;i<8;i++){const r=(await one(`insert into push_outbox(player,kind,msg,dedupe,done_at) values($1,'friend','request',$2,now()) returning id`,[P.paul.id,'cap'+i])).id;await q(`insert into push_log(player,outbox,token,result) values($1,$2,'x','sent')`,[P.paul.id,r])}
await q(`insert into push_outbox(player,kind,msg,dedupe) values($1,'friend','request','t-cap')`,[P.paul.id]);await q(`set role service_role`);
c=(await one(`select push_claim(100) j`)).j;await q(`reset role`);
ok(!c.some(r=>r.player===P.paul.id),'9th push of the day waits for tomorrow');
ok((await one(`select due_at>now() d from push_outbox where dedupe='t-cap'`)).d,'…and is kept, not dropped');

console.log('tournaments');
await q(`update tournaments set created_at=now()-interval '2 hours'`);
const t=(await one(`select tourney_create($1,$2,$3::uuid[]) j`,[P.paul.id,P.paul.sec,[P.kaulin.id]])).j;
ok((await out(P.kaulin.id)).some(r=>r.msg==='tourneyInvite'&&r.args[0]==='Paul'),'tournament invite → push');
const pd=(await out(P.paul.id)).find(r=>r.msg==='tourneyDone');ok(pd&&pd.later,'host gets the result push, scheduled for the end',pd);
await q(`select tourney_answer($1,$2,$3,true)`,[P.kaulin.id,P.kaulin.sec,t.id]);
ok((await out(P.kaulin.id)).find(r=>r.msg==='tourneyDone')?.later,'joining schedules the result push');
await q(`set role service_role`);c=(await one(`select push_claim(100) j`)).j;await q(`reset role`);
ok(!c.some(r=>r.msg==='tourneyDone'),'result push not sent before the tournament ends');

console.log('safety');
await q(`select duo_invite($1,$2,$3,'together-2')`,[P.kaulin.id,P.kaulin.sec,P.paul.id]).catch(()=>{});
await q(`alter table push_outbox rename to push_outbox_x`);
let r2;try{r2=(await one(`select duo_leave($1,$2,(select id from duo_puzzles where a=$3 and status='pending' limit 1)) x`,[P.kaulin.id,P.kaulin.sec,P.kaulin.id]));await q(`select duo_invite($1,$2,$3,'together-3') r`,[P.kaulin.id,P.kaulin.sec,P.paul.id]);ok(true,'game actions still work even if the push queue is broken')}catch(e){ok(false,'game actions survive a broken push queue',e.message)}
await q(`alter table push_outbox_x rename to push_outbox`);
const g2=(await q(`select has_function_privilege('anon','public.register_device(uuid,text,text,text,text,text,int,text)','execute') a, has_function_privilege('anon','public.push_claim(int)','execute') b, has_function_privilege('anon','public.push_report(json)','execute') c, has_table_privilege('anon','public.device_tokens','select') d, has_function_privilege('service_role','public.push_claim(int)','execute') e`))[0];
ok(g2.a&&!g2.b&&!g2.c&&!g2.d&&g2.e,'anon can register a device only; only the service role can claim/report',g2);
const st=(await one(`select push_status($1,$2) j`,[P.paul.id,P.paul.sec])).j;ok(st.devices.length===2&&st.recent.length>0&&st.devices[0].tail.length===6,'push_status shows own devices (token tail only) and recent results',st.devices);
const news=(await one(`select my_news($1,$2,false) j`,[P.kaulin.id,P.kaulin.sec])).j;ok('duo_invites' in news,'my_news unchanged for older apps');
console.log(fails?`${fails} failure(s)`:'all passed');process.exit(fails?1:0);
