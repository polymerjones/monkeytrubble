// Checks the board deals in index.html: every level and every shuffle stays solvable, Kevin is never free at the start of a level
// and sits deep in the board, and a shuffle leaves the cage untouched.  Run: node tools/check-deals.mjs [levels]
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const script=html.slice(html.lastIndexOf('<script>')+8,html.lastIndexOf('</script>'));
const fn=name=>{const start=script.indexOf(`function ${name}(`);if(start<0)throw new Error(`missing ${name}`);let depth=0;for(let i=script.indexOf('){',start)+1;i<script.length;i++){if(script[i]==='{')depth++;else if(script[i]==='}'&&!--depth)return script.slice(start,i+1)}};
const line=prefix=>{const m=script.match(new RegExp(`^\\s*(${prefix}.*)$`,'m'));if(!m)throw new Error(`missing ${prefix}`);return m[1]};
const deck=[...script.matchAll(/^\s+(\w+):\{image:/gm)].map(m=>m[1]).filter(id=>id!=='JOKER'&&id!=='KEVIN');
const game=new Function(`
  const JOKER='JOKER',KEVIN='KEVIN',DECK=${JSON.stringify(deck)};
  ${line('const KEVIN_WINDOW=')}
  ${line('const isMate=')}
  ${line('const shuffleWith=')}
  ${line('const BONUS_PAIR_CHANCE=')}
  ${line('const faceUpShare=')}
  ${['buildLayout','mulberry32','dealUnits','levelUnits','unitsFromSymbols','bonusPairFor'].map(fn).join('\n')}
  const BASE_LAYOUT=buildLayout(),TOTAL=BASE_LAYOUT.length;
  // Same deal as buildLevelBoard, plus the removal order it was built along.
  function levelBoard(level){const rng=mulberry32(level*9973),pos=BASE_LAYOUT.map(p=>({...p,blockers:[...p.blockers]})),trace=[],assignments=dealUnits(pos,levelUnits(rng),rng,{noFreePair:true,freePair:bonusPairFor(level),trace});return{tiles:pos.map(p=>({...p,symbol:assignments.get(p.id)})),order:trace}}
  return {dealUnits,unitsFromSymbols,levelBoard,mulberry32,KEVIN_WINDOW};
`)();
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
for(let level=1;level<=levels;level++){
  const {tiles,order}=game.levelBoard(level),kevin=tiles.find(t=>t.symbol===KEVIN);kevinSpots.push(order.indexOf(kevin.id)/order.length);
  if(!kevin.blockers.length){problems++;console.log(`level ${level}: Kevin is free at the start`)}
  depths.push(depth(tiles,kevin.id));
  const err=replay(tiles,order);if(err){problems++;console.log(`level ${level}: ${err}`)}
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
  catch(e){problems++;console.log(`level ${level}: shuffle with cage [${cage}] threw: ${e.message}`);continue}
  board.forEach(t=>{t.symbol=assignments.get(t.id)});
  if(cage.join()!==before.join()){problems++;console.log(`level ${level}: shuffle changed the cage`)}
  const sorted=s=>[...s].sort().join();
  const counts=sorted([...left.values()].map(t=>t.symbol)),after=sorted(board.map(t=>t.symbol));
  if(counts!==after){problems++;console.log(`level ${level}: shuffle changed which cards are on the board`)}
  const shuffleErr=replay(board,trace,cage);if(shuffleErr){problems++;console.log(`level ${level}: after shuffle with cage [${cage}] (${board.length} cards left): ${shuffleErr}`)}
}
depths.sort((a,b)=>a-b);
kevinSpots.sort((a,b)=>a-b);console.log(`Kevin dealt before the 60% mark (window fallback): ${kevinSpots.filter(x=>x<game.KEVIN_WINDOW[0]-.03).length} level(s)`);const pct=x=>`${Math.round(x*100)}%`;
console.log(`${levels} levels: ${problems} problem(s). Kevin's place in the removal order: ${pct(kevinSpots[0])}–${pct(kevinSpots.at(-1))} (median ${pct(kevinSpots[kevinSpots.length>>1])}). Cards stacked over Kevin: min ${depths[0]}, median ${depths[depths.length>>1]}, max ${depths.at(-1)}`);
process.exit(problems?1:0);
