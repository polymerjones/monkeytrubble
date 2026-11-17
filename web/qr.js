// A small QR code maker for friend links (2026-11-17): byte mode, error correction level L, versions 1-4 (up to 78 bytes). Those
// versions have a single error-correction block and no version info, which keeps this short. Returns a square array of rows
// (1 = dark), without the quiet zone, or null if the text is too long. Mask: the lowest-penalty of the 8 (QR spec rules 1-4).
window.qrMatrix=function(text){
  const data=[...new TextEncoder().encode(text)],CAP=[0,19,34,55,80],ECN=[0,7,10,15,20];
  let v=1;while(v<=4&&data.length+2>CAP[v])v++;if(v>4)return null;
  const bits=[],put=(val,n)=>{for(let i=n-1;i>=0;i--)bits.push(val>>>i&1)};
  put(4,4);put(data.length,8);for(const b of data)put(b,8);
  for(let i=0;i<4&&bits.length<CAP[v]*8;i++)bits.push(0);while(bits.length%8)bits.push(0);
  const cw=[];for(let i=0;i<bits.length;i+=8)cw.push(parseInt(bits.slice(i,i+8).join(''),2));
  for(let p=0;cw.length<CAP[v];p++)cw.push(p%2?0x11:0xEC);
  // Reed-Solomon over GF(256), polynomial 0x11d.
  const EXP=[],LOG=[];for(let i=0,x=1;i<255;i++){EXP[i]=x;LOG[x]=i;x<<=1;if(x&256)x^=0x11d}for(let i=255;i<512;i++)EXP[i]=EXP[i-255];
  const mul=(a,b)=>a&&b?EXP[LOG[a]+LOG[b]]:0;
  let gen=[1];for(let i=0;i<ECN[v];i++){const g=new Array(gen.length+1).fill(0);gen.forEach((c,j)=>{g[j]^=c;g[j+1]^=mul(c,EXP[i])});gen=g}
  const rem=new Array(ECN[v]).fill(0);for(const c of cw){const f=c^rem.shift();rem.push(0);for(let j=0;j<rem.length;j++)rem[j]^=mul(gen[j+1],f)}
  const stream=[];for(const b of [...cw,...rem])for(let i=7;i>=0;i--)stream.push(b>>>i&1);
  // Function patterns: finders with separators, timing, the alignment pattern (v2+), the dark module, reserved format areas.
  const n=17+4*v,base=[...Array(n)].map(()=>new Array(n).fill(null));
  for(const [r0,c0] of [[0,0],[0,n-7],[n-7,0]])for(let dr=-1;dr<=7;dr++)for(let dc=-1;dc<=7;dc++){const r=r0+dr,c=c0+dc;if(r<0||c<0||r>=n||c>=n)continue;
    base[r][c]=dr>=0&&dr<=6&&dc>=0&&dc<=6&&(dr===0||dr===6||dc===0||dc===6||dr>=2&&dr<=4&&dc>=2&&dc<=4)?1:0}
  for(let i=8;i<n-8;i++){base[6][i]=base[i][6]=i%2?0:1}
  if(v>=2)for(let dr=-2;dr<=2;dr++)for(let dc=-2;dc<=2;dc++)base[n-7+dr][n-7+dc]=Math.max(Math.abs(dr),Math.abs(dc))===1?0:1;
  for(let i=0;i<9;i++){if(base[8][i]==null)base[8][i]=0;if(base[i][8]==null)base[i][8]=0}
  for(let i=0;i<8;i++){base[8][n-1-i]=0;base[n-1-i][8]=0}base[n-8][8]=1;
  const fixed=base.map(r=>r.map(c=>c!=null));
  // Data in the zigzag from the bottom right, two columns at a time, skipping the timing column.
  let k=0;for(let right=n-1;right>=1;right-=2){if(right===6)right=5;const up=((right+1)&2)===0;
    for(let vert=0;vert<n;vert++)for(let j=0;j<2;j++){const c=right-j,r=up?n-1-vert:vert;if(!fixed[r][c])base[r][c]=k<stream.length?stream[k++]:0}}
  const MASKS=[(r,c)=>(r+c)%2===0,(r)=>r%2===0,(r,c)=>c%3===0,(r,c)=>(r+c)%3===0,(r,c)=>(Math.floor(r/2)+Math.floor(c/3))%2===0,
    (r,c)=>r*c%2+r*c%3===0,(r,c)=>(r*c%2+r*c%3)%2===0,(r,c)=>((r+c)%2+r*c%3)%2===0];
  function build(mask){const m=base.map((row,r)=>row.map((x,c)=>fixed[r][c]?x:x^(MASKS[mask](r,c)?1:0)));
    let d=1<<3|mask,rm=d;for(let i=0;i<10;i++)rm=(rm<<1)^((rm>>>9)*0x537);const f=((d<<10)|rm)^0x5412,bit=i=>f>>>i&1;
    for(let i=0;i<=5;i++)m[i][8]=bit(i);m[7][8]=bit(6);m[8][8]=bit(7);m[8][7]=bit(8);for(let i=9;i<15;i++)m[8][14-i]=bit(i);
    for(let i=0;i<8;i++)m[8][n-1-i]=bit(i);for(let i=8;i<15;i++)m[n-15+i][8]=bit(i);m[n-8][8]=1;return m}
  function penalty(m){let p=0,dark=0;const lines=[...m,...m[0].map((_,c)=>m.map(r=>r[c]))];
    for(const L of lines){let run=1;for(let i=1;i<=n;i++){if(i<n&&L[i]===L[i-1])run++;else{if(run>=5)p+=run-2;run=1}}
      const s=L.join('');for(const pat of ['10111010000','00001011101'])for(let i=s.indexOf(pat);i>=0;i=s.indexOf(pat,i+1))p+=40}
    for(let r=0;r<n-1;r++)for(let c=0;c<n-1;c++){const x=m[r][c];if(x===m[r][c+1]&&x===m[r+1][c]&&x===m[r+1][c+1])p+=3}
    for(const row of m)for(const x of row)dark+=x;p+=Math.floor(Math.abs(dark*20-n*n*10)/(n*n))*10;return p}
  let best=null,bestP=Infinity;for(let mask=0;mask<8;mask++){const m=build(mask),p=penalty(m);if(p<bestP){best=m;bestP=p}}
  return best};
