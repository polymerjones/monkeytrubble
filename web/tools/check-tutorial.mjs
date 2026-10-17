// Checks the tutorial's scripted board in index.html: the covered card is covered only by the face-down pair and every other card is
// free; the fixed-seed shuffle (TUT_SHUFFLE_SEED, run through the game's own dealUnits) leaves the Joker, the vision card and the drag
// pair face up and the Owl Eyes pair face down; and the cards left for the end are four that never pair, so they fill the cage.
// Run: node tools/check-tutorial.mjs            (--find-seed lists seeds that pass, for when the board changes)
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const script=html.slice(html.lastIndexOf('<script>')+8,html.indexOf('</script>',html.lastIndexOf('<script>')));
const fn=name=>{const start=script.indexOf(`function ${name}(`);if(start<0)throw new Error(`missing ${name}`);let depth=0;for(let i=script.indexOf('){',start)+1;i<script.length;i++){if(script[i]==='{')depth++;else if(script[i]==='}'&&!--depth)return script.slice(start,i+1)}};
const line=prefix=>{const m=script.match(new RegExp(`^\\s*(${prefix}.*)$`,'m'));if(!m)throw new Error(`missing ${prefix}`);return m[1]};
const game=new Function(`const JOKER='JOKER',KEVIN='KEVIN';
  ${line('const TUT_CELLS=')}
  ${line('const TUT_SYMBOLS=')}
  ${line('const KEVIN_WINDOW=')}
  ${line('const isMate=')}
  ${line('const shuffleWith=')}
  ${['buildLayout','mulberry32','dealUnits','unitsFromSymbols'].map(fn).join('\n')}
  return {TUT_CELLS,TUT_SYMBOLS,TUT_FACE_DOWN,TUT_SHUFFLE_SEED,buildLayout,mulberry32,dealUnits,unitsFromSymbols,JOKER,KEVIN};`)();
const {TUT_SYMBOLS,TUT_FACE_DOWN,JOKER,KEVIN}=game;

// The tutorial's own cards, by tile number (see TUT_STEPS): 0/4 the tap pair, 5 the covered card, 6/7 the flip pair, 1 the card
// dragged into the cage before the shuffle. After the shuffle cards are found by symbol.
const DRAG_PAIR='R2_UAKARI',OWL_PAIR='R2_WOOLLY';
const tiles=()=>game.buildLayout(game.TUT_CELLS).map((p,i)=>({...p,n:i,symbol:TUT_SYMBOLS[i],revealed:!TUT_FACE_DOWN.includes(i),active:true}));
const free=(t,all)=>!t.blockers.some(id=>all.find(o=>o.id===id).active);

function check(seed){
  const problems=[],ok=(c,msg)=>{if(!c)problems.push(msg)},all=tiles();
  for(const t of all)if(t.n===5)ok(!free(t,all)&&t.blockers.length===2&&t.blockers.every(id=>['tile-6','tile-7'].includes(id)),'tile 5 is covered by exactly the flip pair');else ok(free(t,all),`tile ${t.n} starts free`);
  ok(all[0].symbol===all[4].symbol&&all[6].symbol===all[7].symbol,'the tap pair and flip pair match');
  // Up to the shuffle: tap pair and flip pair cleared, tile 1 caged.
  for(const n of [0,4,6,7,1])all[n].active=false;const cage=[all[1].symbol];
  const active=all.filter(t=>t.active);ok(active.every(t=>free(t,all)),'every card is free at the shuffle');
  const a=game.dealUnits(active.map(({id,x,y,layer,blockers})=>({id,x,y,layer,blockers})),game.unitsFromSymbols([...active.map(t=>t.symbol),...cage]),game.mulberry32(seed),{caged:cage});
  const before=active.map(t=>t.symbol).sort().join();active.forEach(t=>{t.was=t.symbol;t.symbol=a.get(t.id)});ok(active.map(t=>t.symbol).sort().join()===before,'the shuffle keeps the same cards');
  const up=sym=>active.filter(t=>t.symbol===sym).every(t=>t.revealed);
  ok(up(DRAG_PAIR)&&up(JOKER)&&up(KEVIN),'drag pair, Joker and vision card land face up');
  ok(active.filter(t=>!t.revealed).every(t=>t.symbol===OWL_PAIR),'the Owl Eyes pair lands face down');
  ok(active.filter(t=>t.revealed&&t.symbol!==t.was).length>=5,'at least five face-up cards visibly change');
  // Drag pair, Joker (with the oldest caged card), vision card and the Owl Eyes pair leave; the rest must be four that never pair.
  const left=[...active.filter(t=>![DRAG_PAIR,JOKER,KEVIN,OWL_PAIR].includes(t.symbol)).map(t=>t.symbol),...cage.slice(1)];
  ok(left.length>=4&&new Set(left).size===left.length,'four unmatched cards are left to fill the cage');
  return problems;
}

if(process.argv.includes('--find-seed')){const good=[];for(let s=1;s<=500&&good.length<10;s++)if(!check(s).length)good.push(s);console.log('Seeds that pass:',good.join(', ')||'none');process.exit(0)}
const problems=check(game.TUT_SHUFFLE_SEED);
console.log(problems.length?problems.join('\n'):`Tutorial: ${TUT_SYMBOLS.length} cards, shuffle seed ${game.TUT_SHUFFLE_SEED}, 0 problems.`);
process.exit(problems.length?1:0);
