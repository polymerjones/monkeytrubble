// Checks that the leaderboard server (submit_score in supabase/leaderboard.sql) accepts every rating the game can legitimately
// produce. On 2026-11-16 top players froze on the board: the server capped rating at 200 x (1 + level/10) but the combo chain
// bonus lets a clear score up to 20% more, so their submits were rejected ("rating out of range") and the phone retried forever.
// Run: node tools/check-scoring.mjs
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const sql=readFileSync(new URL('../supabase/leaderboard.sql',import.meta.url),'utf8');
const script=html.slice(html.lastIndexOf('<script>')+8,html.lastIndexOf('</script>'));
const grab=re=>{const m=script.match(re);if(!m)throw new Error(`missing ${re}`);return m[0]};

const {levelPar,levelPoints,ratingOf,chainBonus}=new Function(`
  const CHAIN_BONUS_PER_TIER=${grab(/CHAIN_BONUS_PER_TIER=([\d.]+)/).split('=')[1]},CHAIN_BONUS_MAX=${grab(/CHAIN_BONUS_MAX=([\d.]+)/).split('=')[1]};
  ${grab(/const chainBonus=[^;]+;/)}
  ${grab(/const levelPar=[^;]+;/)}
  ${grab(/function levelPoints\([^)]*\)\{[^\n]*\}/)}
  ${grab(/const ratingOf=[^\n]+;/)}
  return {levelPar,levelPoints,ratingOf,chainBonus}`)();

// The server's cap: p_rating > N * (1 + p_level / 10.0).
const capMatch=sql.match(/p_rating > (\d+) \* \(1 \+ p_level \/ 10\.0\)/);
if(!capMatch)throw new Error('submit_score rating cap not found in leaderboard.sql');
const capPer=Number(capMatch[1]),cap=pLevel=>capPer*(1+pLevel/10);

let fails=0;const check=(ok,msg)=>{if(!ok){fails++;console.error('FAIL',msg)}};
// Same rounding as recordLevelClear: points = round(levelPoints x (1 + chainBonus)).
const clear=(level,ms,assists,chain)=>Math.round(levelPoints(level,ms,assists)*(1+chainBonus(chain)));

// The reported clear: level 39 in 0:58, no assists, a long combo -> +1176; a rating of 1016 at level 40 must be accepted.
check(clear(39,58000,0,8)===1176,`level 39 in 58s should score 1176, got ${clear(39,58000,0,8)}`);
check(1016<=cap(40),`rating 1016 at p_level 40 rejected (cap ${cap(40)})`);

// The best possible clear at every level, and a rating made of ten of them, must fit under the cap the phone is held to
// (it sends p_level = the next level, progress.level).
for(let level=1;level<=300;level++){
  const best=clear(level,1,0,99),rating=ratingOf(Array(10).fill(best));
  if(rating>cap(level+1)){check(false,`level ${level}: max rating ${rating} > server cap ${cap(level+1).toFixed(1)}`);break}
}

if(fails){console.error(`${fails} scoring check(s) failed (server cap ${capPer} x (1 + level/10))`);process.exit(1)}
console.log(`scoring ok: server cap ${capPer} x (1 + level/10) covers every legitimate rating (levels 1-300)`);
