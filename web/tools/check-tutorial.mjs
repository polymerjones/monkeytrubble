// Checks the tutorial's board in index.html (TUT_CELLS, TUT_SYMBOLS, TUT_FACE_DOWN, TUT_SINGLES):
// - every card is a pair except the vision card and the four singles;
// - the face-down cards are pairs, each under a lid except the four-card Owl Eyes group;
// - the two crossed pairs each cover the other's twin;
// - random players (any legal move, including caging cards with no twin in sight) always finish: a full cage gets the tutorial's
//   free RESUME, which pairs caged cards with their board twins and drops the singles, so the board can always be cleared.
// Run: node tools/check-tutorial.mjs
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const script=html.slice(html.lastIndexOf('<script>')+8,html.indexOf('</script>',html.lastIndexOf('<script>')));
const fn=name=>{const start=script.indexOf(`function ${name}(`);if(start<0)throw new Error(`missing ${name}`);let depth=0;for(let i=script.indexOf('){',start)+1;i<script.length;i++){if(script[i]==='{')depth++;else if(script[i]==='}'&&!--depth)return script.slice(start,i+1)}};
const block=prefix=>{const i=script.indexOf(prefix);if(i<0)throw new Error(`missing ${prefix}`);let depth=0;for(let j=i;j<script.length;j++){const c=script[j];if(c==='['||c==='{')depth++;else if(c===']'||c==='}')depth--;else if(c===';'&&!depth)return script.slice(i,j+1)}};
const game=new Function(`const KEVIN='KEVIN';
  ${block('const TUT_CELLS=')}
  ${block('const TUT_SYMBOLS=')}
  ${fn('buildLayout')}
  return {TUT_CELLS,TUT_SYMBOLS,TUT_FACE_DOWN,TUT_SINGLES,buildLayout};`)();
const {TUT_SYMBOLS,TUT_FACE_DOWN,TUT_SINGLES}=game;

const tiles=()=>game.buildLayout(game.TUT_CELLS).map((p,i)=>({...p,n:i,symbol:TUT_SYMBOLS[i],revealed:!TUT_FACE_DOWN.includes(i),active:true}));
const free=(t,all)=>!t.blockers.some(id=>all.find(o=>o.id===id).active);
const problems=[],ok=(c,msg)=>{if(!c)problems.push(msg)},all=tiles();

const counts=new Map();for(const t of all)counts.set(t.symbol,(counts.get(t.symbol)||0)+1);
for(const [sym,c] of counts)ok(sym==='KEVIN'||TUT_SINGLES.includes(sym)?c===1:c===2,`${sym} appears ${c} times`);
ok(TUT_SINGLES.length===4,'four singles');
const down=all.filter(t=>!t.revealed);
ok(down.every(t=>down.some(o=>o!==t&&o.symbol===t.symbol)),'face-down cards are pairs');
ok(down.filter(t=>free(t,all)).length===4,'four face-down cards (the Owl Eyes group) start free; the rest start under lids');
// Crossed pairs: a lid whose twin sits under the other lid of the pair.
const lids=all.filter(t=>t.layer===1),under=l=>all.filter(t=>l.blockers.length===0&&t.blockers.includes(l.id));
const crossed=lids.filter(l=>lids.some(m=>m!==l&&under(m).some(t=>t.symbol===l.symbol)));
ok(crossed.length===4,`two crossed pairs (found ${crossed.length} crossed lids)`);

// Random playouts.
let fulls=0;
for(let run=0;run<2000;run++){
  const b=tiles();let cage=[],guard=0;
  while((b.some(t=>t.active)||cage.length)&&guard++<200){
    const open=b.filter(t=>t.active&&free(t,b)),moves=[];
    for(const t of open)moves.push(t);
    // Nothing left to take but twinless cards in the cage: the game calls it stuck, and the tutorial's free RESUME empties the cage.
    if(!moves.length&&cage.every(s=>TUT_SINGLES.includes(s))&&!b.some(t=>t.active)){cage=[];break}
    if(!moves.length){problems.push(`run ${run}: stuck with ${b.filter(t=>t.active).length} cards and cage [${cage}]`);break}
    // Mostly sensible players: take a caged card's twin or a pair when there is one, otherwise anything.
    const sensible=open.find(t=>cage.includes(t.symbol))||open.find(t=>open.some(o=>o!==t&&o.symbol===t.symbol));
    const t=Math.random()<.7&&sensible?sensible:moves[Math.floor(Math.random()*moves.length)];
    t.active=false;if(t.symbol==='KEVIN')continue;
    const k=cage.indexOf(t.symbol);if(k>=0){cage.splice(k,1);continue}
    cage.push(t.symbol);
    if(cage.length>=4){fulls++;for(const sym of cage){const mate=b.find(o=>o.active&&o.symbol===sym);if(mate)mate.active=false}cage=[]}
  }
}

console.log(problems.length?problems.slice(0,10).join('\n'):`Tutorial: ${TUT_SYMBOLS.length} cards, ${TUT_FACE_DOWN.length} face down, ${TUT_SINGLES.length} singles; 2000 random playouts finish (${fulls} full cages); 0 problems.`);
process.exit(problems.length?1:0);
