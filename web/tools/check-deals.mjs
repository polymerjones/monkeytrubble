// Checks the board deals in index.html: every level and every shuffle stays solvable, Kevin is never free at the start of a level
// and sits deep in the board, and a shuffle leaves the cage untouched.  Run: node tools/check-deals.mjs [levels]
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const script=html.slice(html.lastIndexOf('<script>')+8,html.lastIndexOf('</script>'));
const fn=name=>{const start=script.indexOf(`function ${name}(`);if(start<0)throw new Error(`missing ${name}`);let depth=0;for(let i=script.indexOf('){',start)+1;i<script.length;i++){if(script[i]==='{')depth++;else if(script[i]==='}'&&!--depth)return script.slice(start,i+1)}};
const block=start=>{const i=script.indexOf(start);if(i<0)throw new Error(`missing ${start}`);return script.slice(i,script.indexOf('];',i)+2)};
// The chapter lookup (two lines, ending at its accent field).
const chapterFor=()=>{const i=script.indexOf('const chapterFor=');if(i<0)throw new Error('missing chapterFor');const end='accent:c.pal.accent}};';return script.slice(i,script.indexOf(end,i)+end.length)};
const line=prefix=>{const m=script.match(new RegExp(`^\\s*(${prefix}.*)$`,'m'));if(!m)throw new Error(`missing ${prefix}`);return m[1]};
const deck=[...script.matchAll(/^\s+(\w+):\{image:/gm)].map(m=>m[1]).filter(id=>id!=='JOKER'&&id!=='KEVIN');
// groups: the card groups as [unlockLevel, cards] (default: today's deck as one group).
const makeGame=(groups=[[1,deck]])=>new Function(`
  const JOKER='JOKER',KEVIN='KEVIN',DECK=${JSON.stringify(groups.flatMap(g=>g[1]))},GROUPS=${JSON.stringify(groups)};
  const groupDecks=level=>GROUPS.filter(([at,cards])=>at<=level&&cards.length).map(([,cards])=>cards);
  // Card art, sets and seasons don't matter to the deal checks: every level deals from the plain deck, no Halloween.
  const CARD_DATA={},SET_DECKS={},HALLOWEEN_DECK=[],levelPack=()=>'regular';
  ${line('const ALL_SET=')}
  ${block('const CHAPTERS=[')}
  ${chapterFor()}
  ${line('const KEVIN_WINDOW=')}
  ${block('const LAYOUTS=[')}
  ${line('const layoutFor=')}
  ${line('const TOTAL=')}
  ${line('const START_PAIRS=')}
  ${line('const isMate=')}
  ${line('const shuffleWith=')}
  ${line('const faceUpShare=')}
  ${['buildLayout','mulberry32','dealUnits','levelUnits','unitsFromSymbols','startPairsFor','cageStep','solveLine'].map(fn).join('\n')}
  // Same deal as buildLevelBoard, plus the removal order it was built along and the start pairs.
  function levelBoard(level,easy=false){const rng=mulberry32(level*9973),pos=buildLayout(layoutFor(level,easy).cells),freePairs=startPairsFor(pos,startPairsAt(level,easy),rng),trace=[],assignments=dealUnits(pos,levelUnits(rng,level,pos.length),rng,{freePairs,trace,maxOpen:maxOpenAt(level,easy)});return{tiles:pos.map(p=>({...p,symbol:assignments.get(p.id)})),order:trace,freePairs,layout:layoutFor(level,easy).id}}
  return {dealUnits,unitsFromSymbols,levelBoard,mulberry32,KEVIN_WINDOW,solveLine,startPairsAt};
`)();
const game=makeGame();
const {JOKER,KEVIN}={JOKER:'JOKER',KEVIN:'KEVIN'};
const mates=(a,b)=>a!==KEVIN&&b!==KEVIN&&(a===b||a===JOKER||b===JOKER);

// Replays a removal order under the game's cage rules: a card pairs with the same card in the cage, else with a caged joker; a joker pairs
// with the oldest caged card; Kevin leaves on his own; four unmatched cards lose. Returns an error string, or null when the order clears.
function replay(tiles,order,cage=[]){
  const sym=new Map(tiles.map(t=>[t.id,t.symbol])),blockers=new Map(tiles.map(t=>[t.id,t.blockers])),left=new Set(sym.keys());cage=[...cage];
  for(const id of order){
    if(blockers.get(id).some(b=>left.has(b)))return `${id} taken while blocked`;
    left.delete(id);const s=sym.get(id);if(s===KEVIN)continue;
    let k=s===JOKER?(cage.length?0:-1):cage.indexOf(s);if(k<0&&s!==JOKER)k=cage.indexOf(JOKER);
    if(k>=0)cage.splice(k,1);else cage.push(s);
    if(cage.length>=4)return `cage overflow at ${id} [${cage}]`;
  }
  return left.size?'cards left over':cage.length?`cage left holding [${cage}]`:null
}
const depth=(tiles,id)=>{const byId=new Map(tiles.map(t=>[t.id,t])),seen=new Set(),walk=i=>{for(const b of byId.get(i).blockers)if(!seen.has(b)){seen.add(b);walk(b)}};walk(id);return seen.size};

const levels=Number(process.argv[2])||300;let problems=0;const depths=[],kevinSpots=[];
// Normal levels, then the same levels on Easy (bonus pair every level).
for(let run=0;run<levels*2;run++){
  const level=run%levels+1,easy=run>=levels;
  const {tiles,order}=game.levelBoard(level,easy),kevin=tiles.find(t=>t.symbol===KEVIN);kevinSpots.push(order.indexOf(kevin.id)/order.length);
  if(!kevin.blockers.length){problems++;console.log(`${easy?'easy ':''}level ${level}: Kevin is free at the start`)}
  depths.push(depth(tiles,kevin.id));
  const err=replay(tiles,order);if(err){problems++;console.log(`${easy?'easy ':''}level ${level}: ${err}`)}
  // Shuffle from a random mid-level position: play a random legal line, stop with 0-3 cards caged, re-deal the board around the cage.
  const rng=game.mulberry32(level*31),left=new Map(tiles.map(t=>[t.id,{...t}]));let cage=[];
  const target=Math.floor(rng()*tiles.length*.7);
  for(let n=0;n<target;n++){
    const free=[...left.values()].filter(t=>!t.blockers.some(id=>left.has(id))),t=free[Math.floor(rng()*free.length)];if(!t)break;
    let k=t.symbol===KEVIN?null:t.symbol===JOKER?(cage.length?0:-1):cage.indexOf(t.symbol);if(k===-1&&t.symbol!==JOKER)k=cage.indexOf(JOKER);
    if(k===null){left.delete(t.id);continue}
    if(k<0&&cage.length>=3)break;
    const jokerClear=k>=0&&(t.symbol===JOKER||cage[k]===JOKER);left.delete(t.id);cage=k>=0?cage.filter((_,i)=>i!==k):[...cage,t.symbol];
    // Like rebalanceAfterJoker: a joker clear leaves two symbols without partners, so one board card is repainted.
    if(jokerClear){const counts=new Map();for(const s of [...[...left.values()].map(t=>t.symbol),...cage])if(s!==KEVIN&&s!==JOKER)counts.set(s,(counts.get(s)||0)+1);const odd=[...counts].filter(([,c])=>c%2).map(([s])=>s);if(odd.length>=2){const [a,b]=odd,pick=[...left.values()].find(t=>t.symbol===a||t.symbol===b);if(pick)pick.symbol=pick.symbol===a?b:a;else{const i=cage.findIndex(s=>s===a||s===b);cage.splice(i,1)}}}
  }
  const board=[...left.values()].map(t=>({...t,blockers:t.blockers.filter(id=>left.has(id))})),before=[...cage];
  if(!board.length)continue;
  let assignments;const trace=[];
  try{assignments=game.dealUnits(board.map(({id,x,y,layer,blockers})=>({id,x,y,layer,blockers})),game.unitsFromSymbols([...board.map(t=>t.symbol),...cage]),rng,{caged:cage,trace})}
  catch(e){problems++;console.log(`${easy?'easy ':''}level ${level}: shuffle with cage [${cage}] threw: ${e.message}`);continue}
  board.forEach(t=>{t.symbol=assignments.get(t.id)});
  if(cage.join()!==before.join()){problems++;console.log(`${easy?'easy ':''}level ${level}: shuffle changed the cage`)}
  const sorted=s=>[...s].sort().join();
  const counts=sorted([...left.values()].map(t=>t.symbol)),after=sorted(board.map(t=>t.symbol));
  if(counts!==after){problems++;console.log(`${easy?'easy ':''}level ${level}: shuffle changed which cards are on the board`)}
  const shuffleErr=replay(board,trace,cage);if(shuffleErr){problems++;console.log(`${easy?'easy ':''}level ${level}: after shuffle with cage [${cage}] (${board.length} cards left): ${shuffleErr}`)}
}
depths.sort((a,b)=>a-b);
// Card groups: a fake Group 2 (10 cards, unlocks at level 10) must leave levels 1-9 exactly as they are without it, keep every
// later board solvable, and split each level's 22 symbols (21 pairs + the joker's partner) evenly between the groups.
{const fake=Array.from({length:10},(_,i)=>`G2_${i}`),mixed=makeGame([[1,deck],[10,fake]]);
  for(let level=1;level<=Math.min(levels,300);level++){
    const {tiles,order}=mixed.levelBoard(level),syms=tiles.map(t=>t.symbol).filter(s=>s!==KEVIN&&s!==JOKER);
    if(level<10){if(JSON.stringify(syms)!==JSON.stringify(game.levelBoard(level).tiles.map(t=>t.symbol).filter(s=>s!==KEVIN&&s!==JOKER))){problems++;console.log(`groups: level ${level} changed before Group 2 unlocks`)}continue}
    const err=replay(tiles,order);if(err){problems++;console.log(`groups: level ${level}: ${err}`)}
    // 22 symbols (21 pairs + the joker's partner) split 11/11: 22 cards each, give or take the joker's partner.
    const g2=syms.filter(s=>s.startsWith('G2_')).length;
    if(syms.some(s=>!s)||g2<21||g2>22){problems++;console.log(`groups: level ${level} has ${g2} Group 2 cards of ${syms.length}`)}
  }}
// Owl Eyes hints: the solver must find a clearing line from every level's start and from a random mid-level position.
{let found=0,gaveUp=0,slowest=0;
  for(let level=1;level<=Math.min(levels,200);level++){
    const {tiles}=game.levelBoard(level),rng=game.mulberry32(level*57),left=new Map(tiles.map(t=>[t.id,t]));let cage=[];
    for(const stage of ['start','mid']){
      if(stage==='mid'){const sol=game.solveLine([...left.values()],cage);if(!sol)break;for(const t of sol.slice(0,8+Math.floor(rng()*14))){left.delete(t.id);let k=t.symbol===KEVIN?null:t.symbol===JOKER?(cage.length?0:-1):cage.indexOf(t.symbol);if(k===-1&&t.symbol!==JOKER)k=cage.indexOf(JOKER);if(k===null)continue;cage=k>=0?cage.filter((_,i)=>i!==k):[...cage,t.symbol]}}
      const board=[...left.values()],t0=performance.now(),path=game.solveLine(board,cage);slowest=Math.max(slowest,performance.now()-t0);
      if(path===undefined){gaveUp++;console.log(`hint: level ${level} (${stage}) search gave up`);continue}
      if(!path){problems++;console.log(`hint: level ${level} (${stage}) found no line`);continue}
      const err=replay(board,path.map(t=>t.id),cage);if(err){problems++;console.log(`hint: level ${level} (${stage}) line fails: ${err}`)}else found++
    }
  }
  console.log(`Owl Eyes: ${found} lines found, ${gaveUp} gave up, slowest ${Math.round(slowest)}ms`)}
// Start: every level opens with its start pairs (both cards playable and matching) and enough playable cards: 10 up to the jungle
// and on Easy (the chapter shapes Monkey Head, Banana and Temple open 10-11), at least 3 on the cascade shapes from level 11
// (few open cards on purpose); count shapes.
{const shapes={};for(let level=1;level<=levels;level++)for(const easy of [false,true]){
  const {tiles,freePairs,layout}=game.levelBoard(level,easy),byId=new Map(tiles.map(t=>[t.id,t])),free=tiles.filter(t=>!t.blockers.length);shapes[layout]=(shapes[layout]||0)+1;
  const want=game.startPairsAt(level,easy);if(freePairs.length!==want){problems++;console.log(`${easy?'easy ':''}level ${level}: ${freePairs.length} start pairs`)}
  for(const [a,b] of freePairs)if(byId.get(a).symbol!==byId.get(b).symbol||byId.get(a).blockers.length||byId.get(b).blockers.length){problems++;console.log(`${easy?'easy ':''}level ${level}: start pair ${a}/${b} not an open match`)}
  if(free.length<(easy||level<=10?10:3)){problems++;console.log(`${easy?'easy ':''}level ${level}: only ${free.length} playable at the start`)}}
  console.log('Shapes dealt:',JSON.stringify(shapes))}
kevinSpots.sort((a,b)=>a-b);console.log(`Kevin dealt before the window (fallback): ${kevinSpots.filter(x=>x<game.KEVIN_WINDOW[0]-.03).length} level(s)`);const pct=x=>`${Math.round(x*100)}%`;
console.log(`${levels} levels: ${problems} problem(s). Kevin's place in the removal order: ${pct(kevinSpots[0])}–${pct(kevinSpots.at(-1))} (median ${pct(kevinSpots[kevinSpots.length>>1])}). Cards stacked over Kevin: min ${depths[0]}, median ${depths[depths.length>>1]}, max ${depths.at(-1)}`);
process.exit(problems?1:0);
