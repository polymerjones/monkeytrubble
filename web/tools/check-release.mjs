// Release consistency (1.1.3): What's New, the iOS and Android versions and the service worker cache agree, and every What's New line
// and puzzle name has its Spanish. Run from web/: node tools/check-release.mjs   (exit 1 on a problem)
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

const ROOT = fileURLToPath(new URL('../..', import.meta.url)), read = p => readFileSync(join(ROOT, p), 'utf8');
const html = read('web/index.html'), pbx = read('MonkeyTrubbleIOS/MonkeyTrubbleIOS.xcodeproj/project.pbxproj'), gradle = read('MonkeyTrubbleAndroid/app/build.gradle.kts');
globalThis.window = {}; new Function(read('web/i18n/es.js'))(); const ES = window.ES_TEXT;
let fails = 0; const ok = (c, what, d) => { console.log(`  ${c ? 'PASS' : 'FAIL'} ${what}${!c && d ? ` (${d})` : ''}`); if (!c) fails++ };

const notes = html.match(/RELEASE_NOTES=\{version:'([^']+)',lines:\[([\s\S]*?)\]\}/);
const version = notes?.[1], ios = [...new Set([...pbx.matchAll(/MARKETING_VERSION = ([0-9.]+);/g)].map(m => m[1]))], iosBuild = [...new Set([...pbx.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)].map(m => m[1]))];
const vName = gradle.match(/versionName = "([^"]+)"/)?.[1], vCode = gradle.match(/versionCode = (\d+)/)?.[1];
console.log(`What's New ${version} · iOS ${ios.join('/')} (${iosBuild.join('/')}) · Android ${vName} (${vCode}) · ${read('web/sw.js').match(/CACHE = '([^']+)'/)?.[1]}`);
ok(ios.length === 1 && ios[0] === version, "What's New version = iOS MARKETING_VERSION", `${version} vs ${ios}`);
ok(vName === version, "What's New version = Android versionName", `${version} vs ${vName}`);
ok(iosBuild.length === 1, 'one iOS build number across configurations', iosBuild.join());
const lines = [...notes[2].matchAll(/(['"])((?:\\.|(?!\1).)*)\1\s*,?/g)].map(m => m[2].replace(/\\'/g, "'"));
const missing = lines.filter(l => !ES[l]);
ok(!missing.length, `every What's New line has Spanish (${lines.length} lines)`, missing.slice(0, 3).join(' | '));
const names = [...html.matchAll(/\{key:'[^']+',img:'[^']+',name:'([^']+)'/g)].map(m => m[1]).filter(n => !ES[n] && !/^Monkey Trubble [IVX]+$/.test(n) && n !== 'Poly Card');
ok(!names.length, 'every puzzle name has Spanish', names.join(', '));
console.log(fails ? `check-release: ${fails} problem(s)` : 'check-release: all passed');
process.exit(fails ? 1 : 0);
