// Push sender (web/supabase/functions/push/sender.ts) against fake APNs, FCM, Google OAuth and the database RPCs. Real keys are
// generated here (never real credentials). Run: node tests/push/check-sender.mjs   (Node 23.6+ runs the .ts directly)
import {makeSender, words, quietFor} from '../../web/supabase/functions/push/sender.ts';
let fails=0;const ok=(c,w,d)=>{console.log(`  ${c?'PASS':'FAIL'} ${w}${!c&&d!==undefined?' '+JSON.stringify(d):''}`);if(!c)fails++};
const pem=(der,label)=>`-----BEGIN ${label}-----\n${Buffer.from(der).toString('base64').match(/.{1,64}/g).join('\n')}\n-----END ${label}-----`;
const ec=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const rsa=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const env={SUPABASE_URL:'https://db.test',SERVICE_ROLE_KEY:'svc',APNS_KEY_P8:pem(await crypto.subtle.exportKey('pkcs8',ec.privateKey),'PRIVATE KEY'),APNS_KEY_ID:'KEY123',APNS_TEAM_ID:'976XKW42U9',APNS_BUNDLE_ID:'com.paulfisher.MonkeyTrubble',
  FCM_SERVICE_ACCOUNT:JSON.stringify({project_id:'monkey-test',client_email:'push@monkey-test.iam',private_key:pem(await crypto.subtle.exportKey('pkcs8',rsa.privateKey),'PRIVATE KEY')})};
const b64=s=>Buffer.from(s.replace(/-/g,'+').replace(/_/g,'/'),'base64');
const verify=async(token,key,alg)=>{const [h,c,s]=token.split('.');return crypto.subtle.verify(alg,key,b64(s),new TextEncoder().encode(`${h}.${c}`))};

console.log('words and quiet hours');
ok(words('duoInvite','es',['Kaulin'])==='🧩 ¡Kaulin quiere armar un puzzle contigo!','Spanish line with the name');
ok(words('nope','en',[]).length>0,'unknown message still says something');
ok(words('request','en',['A'.repeat(80)]).length<60,'long names are cut');
ok(quietFor(new Date('2026-11-26T15:00:00Z'),-300)===0,'10:00 in New York: send now');
ok(quietFor(new Date('2026-11-27T04:00:00Z'),-300)===9*3600,'23:00 in New York: wait 9h until 08:00',quietFor(new Date('2026-11-27T04:00:00Z'),-300));
ok(quietFor(new Date('2026-11-26T06:30:00Z'),60)===30*60,'07:30 in Madrid: wait 30m');

console.log('a run');
const calls=[];let reported=null,oauth=0;
const pushes=[{id:1,player:'p1',kind:'duo',msg:'duoInvite',args:['Paul'],attempts:1,devices:[
  {token:'ios-good',platform:'ios',env:'prod',lang:'en',tz_min:0},{token:'ios-dead',platform:'ios',env:'sandbox',lang:'en',tz_min:0},
  {token:'and-good',platform:'android',env:'prod',lang:'es',tz_min:0},{token:'and-dead',platform:'android',env:'prod',lang:'en',tz_min:0},
  {token:'and-busy',platform:'android',env:'prod',lang:'en',tz_min:0},{token:'ios-night',platform:'ios',env:'prod',lang:'en',tz_min:-720}]}];
const fake=async(url,opt)=>{calls.push({url,opt});const J=(o,s=200,h={})=>new Response(JSON.stringify(o),{status:s,headers:{'content-type':'application/json',...h}});
  if(url.endsWith('/rpc/push_claim'))return J(calls.filter(c=>c.url.endsWith('push_claim')).length===1?pushes:[]);
  if(url.endsWith('/rpc/push_report')){reported=JSON.parse(opt.body).p_results;return J(reported.length)}
  if(url==='https://oauth2.googleapis.com/token'){oauth++;return J({access_token:'ya29.test',expires_in:3600})}
  if(url.includes('push.apple.com/3/device/ios-dead'))return J({reason:'BadDeviceToken'},400);
  if(url.includes('push.apple.com/3/device/'))return new Response('',{status:200});
  if(url.includes('fcm.googleapis.com')){const t=JSON.parse(opt.body).message.token;if(t==='and-dead')return J({error:{status:'NOT_FOUND',details:[{errorCode:'UNREGISTERED'}]}},404);
    if(t==='and-busy')return J({error:{status:'UNAVAILABLE'}},503,{'retry-after':'120'});return J({name:'projects/x/messages/1'})}
  return new Response('no route '+url,{status:500})};
const now=()=>new Date('2026-11-26T15:00:00Z');
const run=makeSender(env,fake,now);const out=await run();
const R=Object.fromEntries(reported.map(r=>[r.token,r]));
ok(out.claimed===1&&reported.length===6,'every device of the push gets a result',out);
ok(R['ios-good'].result==='sent'&&R['and-good'].result==='sent','iOS and Android deliveries reported sent');
ok(R['ios-dead'].result==='dead'&&R['and-dead'].result==='dead','dead tokens reported (APNs BadDeviceToken, FCM UNREGISTERED)');
ok(R['and-busy'].result==='retry'&&R['and-busy'].retry_in_s>=120,'503 → retry, honoring Retry-After',R['and-busy']);
ok(R['ios-night'].result==='quiet'&&R['ios-night'].retry_in_s===5*3600,'03:00 on that device → quiet until 08:00',R['ios-night']);
const ap=calls.find(c=>c.url.includes('/3/device/ios-good'));
ok(ap.url.startsWith('https://api.push.apple.com/'),'production APNs host for prod tokens');
ok(calls.some(c=>c.url.startsWith('https://api.sandbox.push.apple.com/3/device/ios-dead')),'sandbox host for development builds');
ok(ap.opt.headers['apns-topic']==='com.paulfisher.MonkeyTrubble'&&ap.opt.headers['apns-push-type']==='alert','APNs topic and push type');
const apBody=JSON.parse(ap.opt.body);ok(apBody.kind==='duo'&&/Paul wants to build/.test(apBody.aps.alert.body),'payload carries kind for tap routing',apBody);
const jwtApns=ap.opt.headers.authorization.split(' ')[1];
ok(await verify(jwtApns,ec.publicKey,{name:'ECDSA',hash:'SHA-256'}),'APNs provider token is a valid ES256 signature');
ok(JSON.parse(b64(jwtApns.split('.')[0])).kid==='KEY123'&&JSON.parse(b64(jwtApns.split('.')[1])).iss==='976XKW42U9','…with key id and team id');
const oa=calls.find(c=>c.url==='https://oauth2.googleapis.com/token');const assertion=new URLSearchParams(oa.opt.body).get('assertion');
ok(await verify(assertion,rsa.publicKey,{name:'RSASSA-PKCS1-v1_5'}),'Google OAuth assertion is a valid RS256 signature');
const fc=JSON.parse(calls.find(c=>c.url.includes('fcm')&&JSON.parse(c.opt.body).message.token==='and-good').opt.body).message;
ok(fc.data.kind==='duo'&&fc.android.notification.channel_id==='social'&&/Paul quiere/.test(fc.notification.body),'FCM message: kind, channel, Spanish text',fc);
ok(calls.filter(c=>c.url.includes('push.apple.com')).every(c=>c.opt.headers.authorization===ap.opt.headers.authorization),'one APNs token reused across sends');
await run();ok(oauth===1,'Google token reused on the next run');
ok(!JSON.stringify(calls.map(c=>c.opt?.body||'')).includes('PRIVATE KEY'),'private keys never leave the function');

console.log('not configured');
const bare=makeSender({SUPABASE_URL:'https://db.test',SERVICE_ROLE_KEY:'svc'},fake,now);calls.length=0;reported=null;await bare();
ok(reported.every(r=>r.result==='retry'&&/not configured/.test(r.detail)||r.result==='quiet'),'no keys yet: everything waits (retry), nothing is lost',reported.map(r=>r.detail));
console.log(fails?`${fails} failure(s)`:'all passed');process.exit(fails?1:0);
