import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
import {readFileSync} from 'node:fs';
export async function fresh(){const db=new PGlite({extensions:{pgcrypto}});
  await db.exec(`create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions; create role anon; create role authenticated;`);
  await db.exec(readFileSync(new URL('../../web/supabase/leaderboard.sql', import.meta.url),'utf8'));return db}
if(process.argv[2]==='--load-only'){try{const db=await fresh();console.log('schema loaded OK');const r=await db.query(`select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'`);console.log('functions',r.rows[0])}catch(e){console.log('ERR',e.message,e.position??'')}}
