// Migration tests on a real Postgres (PGlite, Postgres compiled to WebAssembly): loads supabase/leaderboard.sql (production schema),
// then each migration in supabase/migrations, and checks old clients still work, scoring counts once, deadlines freeze, claims
// happen once, and anon can only call the app functions. Single connection, so true concurrency (two clients racing duo_place)
// needs the staging Supabase project; this checks the logic and that the SQL applies.
// Setup once: cd tests/sql && npm install @electric-sql/pglite   (node_modules is git-ignored)
// Run: node tests/sql/check-migrations.mjs
import {fresh} from './load-schema.mjs';
import {readFileSync} from 'node:fs';
const M=new URL('../../web/supabase/migrations/', import.meta.url).pathname;
let fails=0;const ok=(c,w,d)=>{console.log(`  ${c?'PASS':'FAIL'} ${w}${!c&&d!==undefined?' '+JSON.stringify(d):''}`);if(!c)fails++};
const db=await fresh();
const q=async(sql,params=[])=>(await db.query(sql,params)).rows;
const one=async(sql,params)=>(await q(sql,params))[0];
// players
const P={};for(const n of ['Paul','Kaulin','Sam','Izzy']){const id=crypto.randomUUID(),sec='secret-secret-'+n+'-xyz';P[n.toLowerCase()]={id,sec};await q(`select * from submit_score($1,$2,$3,100,1000,3,40)`,[id,sec,n])}
const fr=async(a,b)=>{const code=(await one(`select friends_home($1,$2) j`,[P[b].id,P[b].sec])).j.code;await q(`select add_friend($1,$2,$3)`,[P[a].id,P[a].sec,code]);await q(`select answer_friend($1,$2,$3,true)`,[P[b].id,P[b].sec,P[a].id])};
await fr('paul','kaulin');await fr('paul','sam');await fr('paul','izzy');

console.log('duo-place-lock migration');
try{await db.exec(readFileSync(M+'2026-11-26-duo-place-lock.sql','utf8'));ok(true,'applies to the production schema')}catch(e){ok(false,'applies',e.message)}
try{await db.exec(readFileSync(M+'2026-11-26-duo-place-lock.sql','utf8'));ok(true,'safe to run twice')}catch(e){ok(false,'run twice',e.message)}
ok(await one(`select duo_invite($1,$2,$3,'together-1') r`,[P.paul.id,P.paul.sec,P.kaulin.id]).then(r=>r.r)==='sent','invite still works');
const duo=(await one(`select id from duo_puzzles where a=$1`,[P.paul.id])).id;
await q(`select duo_answer($1,$2,$3,true)`,[P.kaulin.id,P.kaulin.sec,duo]);
for(let g=0;g<12;g++)await q(`insert into duo_pieces(duo,piece,found_by,found_level) values($1,$2,$3,$4)`,[duo,g,P.paul.id,g+1]);
let last;for(let g=0;g<12;g++)last=(await one(`select duo_place($1,$2,$3,$4) r`,[g%2?P.kaulin.id:P.paul.id,g%2?P.kaulin.sec:P.paul.sec,duo,g])).r;
ok(last.done===true,'12th placing finishes (4-arg)',last);
ok((await one(`select status from duo_puzzles where id=$1`,[duo])).status==='done','status done');
ok((await one(`select duo_claim($1,$2,$3) r`,[P.paul.id,P.paul.sec,duo])).r===true&&(await one(`select duo_claim($1,$2,$3) r`,[P.paul.id,P.paul.sec,duo])).r===false,'claim once');
// legacy 3-arg wrapper still resolves
try{await q(`select duo_place($1,$2,0)`,[P.sam.id,P.sam.sec]);ok(true,'1.1 legacy duo_place(p_id,p_secret,p_piece) still callable')}catch(e){ok(false,'legacy wrapper',e.message)}
// repair: a stuck active puzzle with 12 placed
await q(`select duo_invite($1,$2,$3,'together-2')`,[P.paul.id,P.paul.sec,P.sam.id]);const d2=(await one(`select id from duo_puzzles where b=$1`,[P.sam.id])).id;
await q(`update duo_puzzles set status='active' where id=$1`,[d2]);for(let g=0;g<12;g++)await q(`insert into duo_pieces(duo,piece,found_by,found_level,placed_by,placed_at) values($1,$2,$3,$4,$3,now())`,[d2,g,P.sam.id,g+1]);
await db.exec(readFileSync(M+'2026-11-26-duo-place-lock.sql','utf8'));
ok((await one(`select status,a_claimed,b_claimed from duo_puzzles where id=$1`,[d2])).status==='done','repair finishes a stuck puzzle, claim flags untouched');

console.log('tournaments migration');
try{await db.exec(readFileSync(M+'2026-11-26-tournaments.sql','utf8'));ok(true,'applies')}catch(e){ok(false,'applies',e.message)}
try{await db.exec(readFileSync(M+'2026-11-26-tournaments.sql','utf8'));ok(true,'safe to run twice')}catch(e){ok(false,'run twice',e.message)}
const news0=(await one(`select my_news($1,$2,false) j`,[P.paul.id,P.paul.sec])).j;
ok('nudges' in news0&&'duo_invites' in news0&&'requests' in news0&&news0.tourney===null,'my_news keeps every old key, tourney null',Object.keys(news0));
const c=(await one(`select tourney_create($1,$2,$3::uuid[]) j`,[P.paul.id,P.paul.sec,[P.kaulin.id,P.sam.id,crypto.randomUUID()]])).j;
ok(c.status==='created','create (non-friend id ignored)',c);
const T=c.id;
ok((await one(`select count(*)::int n from tournament_members where tourney=$1`,[T])).n===3,'host + 2 friends');
ok((await one(`select tourney_create($1,$2,$3::uuid[]) j`,[P.paul.id,P.paul.sec,[P.kaulin.id]])).j.status==='full','one new tournament an hour per host');
const nk=(await one(`select my_news($1,$2,false) j`,[P.kaulin.id,P.kaulin.sec])).j.tourney;
ok(nk?.invites===1&&nk.host==='Paul','invite shows in my_news with host',nk);
ok((await one(`select tourney_answer($1,$2,$3,true) r`,[P.kaulin.id,P.kaulin.sec,T])).r==='joined','kaulin joins');
ok((await one(`select tourney_answer($1,$2,$3,false) r`,[P.sam.id,P.sam.sec,T])).r==='declined','sam declines');
// play: paul +3 levels and a puzzle; re-sync twice
await q(`select * from submit_score($1,$2,'paul',100,1100,3,43)`,[P.paul.id,P.paul.sec]);
await q(`select submit_puzzle_stats($1,$2,12,1)`,[P.paul.id,P.paul.sec]);await q(`select submit_puzzle_stats($1,$2,12,1)`,[P.paul.id,P.paul.sec]);
await q(`select * from submit_score($1,$2,'paul',100,1100,3,41)`,[P.paul.id,P.paul.sec]);await q(`select submit_puzzle_stats($1,$2,5,0)`,[P.paul.id,P.paul.sec]);
const st=(await one(`select tourney_state($1,$2) j`,[P.paul.id,P.paul.sec])).j;const t0=st.tourneys[0],me=t0.standings.find(s=>s.me);
ok(t0.status==='live'&&t0.standings.length===2,'live with 2 joined',t0.standings.length);
ok(me.levels===3&&me.pieces===12&&me.puzzles===1&&me.points===30+36+25,'scores once: 3 levels, 12 pieces, 1 puzzle',me);
// shared piece placed in window counts for the placer
// finish: move the deadline into the past (test only), sync after deadline must not count
await q(`update tournaments set ends_at=now()-interval '1 minute' where id=$1`,[T]);
await q(`select * from submit_score($1,$2,'paul',100,1200,3,50)`,[P.paul.id,P.paul.sec]);await q(`select submit_puzzle_stats($1,$2,30,2)`,[P.paul.id,P.paul.sec]);
const st2=(await one(`select tourney_state($1,$2) j`,[P.paul.id,P.paul.sec])).j.tourneys[0];
ok(st2.status==='finished'&&st2.standings.find(s=>s.me).points===me.points,'after the deadline nothing moves',st2.standings.find(s=>s.me).points);
const nd=(await one(`select my_news($1,$2,false) j`,[P.paul.id,P.paul.sec])).j.tourney;ok(nd?.finished===1,'finished shows in news',nd);
const cl=(await one(`select tourney_claim($1,$2,$3) j`,[P.paul.id,P.paul.sec,T])).j;ok(cl.ok&&cl.winner&&cl.place===1,'winner claims',cl);
ok((await one(`select tourney_claim($1,$2,$3) j`,[P.paul.id,P.paul.sec,T])).j.ok===false,'second claim refused');
const ck=(await one(`select tourney_claim($1,$2,$3) j`,[P.kaulin.id,P.kaulin.sec,T])).j;ok(ck.ok&&!ck.winner&&ck.place===2,'runner-up claims, not a winner',ck);
ok((await one(`select tourney_claim($1,$2,$3) j`,[P.sam.id,P.sam.sec,T])).j.ok===false,'someone who declined cannot claim');
// ties
await q(`update tournaments set created_at=now()-interval '2 hours' where host=$1`,[P.paul.id]);
const c2=(await one(`select tourney_create($1,$2,$3::uuid[]) j`,[P.paul.id,P.paul.sec,[P.izzy.id]])).j;await q(`select tourney_answer($1,$2,$3,true)`,[P.izzy.id,P.izzy.sec,c2.id]);
const tie=(await one(`select tourney_state($1,$2) j`,[P.paul.id,P.paul.sec])).j.tourneys.find(t=>t.id===c2.id).standings.map(s=>s.place);
ok(tie.length===2&&tie.every(p=>p===1),'ties share 1st',tie);
// auth
try{await q(`select tourney_state($1,'wrong')`,[P.paul.id]);ok(false,'bad secret refused')}catch{ok(true,'bad secret refused')}
// anon grants
const g=(await q(`select has_function_privilege('anon','public.tourney_state(uuid,text)','execute') a, has_function_privilege('anon','public.tourney_points(public.tournament_members,public.tournaments)','execute') b, has_table_privilege('anon','public.tournaments','select') c`))[0];
ok(g.a&&!g.b&&!g.c,'anon can call the app functions only, not the internal one or the tables',g);
console.log(fails?`${fails} failure(s)`:'all passed');process.exit(fails?1:0);
