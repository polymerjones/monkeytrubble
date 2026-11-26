// Social Lab (dev only, 2026-11-26): a fake Supabase for the sandbox profile. index.html loads this file only when the lab is on
// (dev mode + Dev Tools › SOCIAL LAB), and lbCall sends every RPC here instead of the network, so lab play never reaches the real
// leaderboard, friends, shared puzzles or tournaments. The rules copy supabase/leaderboard.sql (one shared piece per level, 6 a day, 5
// open puzzles, claim once, the 12th placing finishes the puzzle, tournament scoring from snapshots). State lives in localStorage
// (monkeyTrubble.lab.server); the lab clock (monkeyTrubble.lab.clock, an offset in ms) is shared with the page for time warp.
(() => {
  const KEY = 'monkeyTrubble.lab.server', CLOCK = 'monkeyTrubble.lab.clock';
  const now = () => Date.now() + (Number(localStorage.getItem(CLOCK)) || 0);
  const iso = t => new Date(t).toISOString();
  const BOT_NAMES = ['Kaulin', 'Sam', 'Izzy', 'Marco', 'Bea', 'Tavi', 'Nora', 'Juno'];
  const BOT_AVATARS = ['M7535', 'M7547', 'M7550', 'M7572', 'R1_CAPUCHIN', 'R2_UAKARI', 'S1_MANDRILL', 'APE_ORANGUTAN'];
  const fresh = () => ({ players: {}, links: [], nudges: [], duos: [], pieces: [], tourneys: [], members: [], seq: 1, fail: 0, slowMs: 0, offline: false, race: false, log: [] });
  let S; try { S = JSON.parse(localStorage.getItem(KEY)) || fresh() } catch { S = fresh() }
  for (const [k, v] of Object.entries(fresh())) if (S[k] === undefined) S[k] = v;
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(S)) } catch {} };
  const log = t => { S.log.unshift(`${new Date(now()).toLocaleTimeString()} ${t}`); S.log.length = Math.min(S.log.length, 30); save(); window.__labRender?.() };
  const id = () => `lab-${(S.seq++).toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  const P = pid => S.players[pid];
  const tierFor = r => r >= 600 ? 'Silverback' : r >= 400 ? 'Gold' : r >= 200 ? 'Silver' : 'Bronze';
  const row = (p, rank) => ({ rank: rank ?? rankOf(p), id: p.id, name: p.name, score: p.score, rating: p.rating, tier: p.tier, streak: p.streak, xp: p.xp, level: p.level, avatar: p.avatar });
  const rankOf = p => 1 + Object.values(S.players).filter(o => o.score > p.score).length;
  const mini = p => ({ id: p.id, name: p.name, avatar: p.avatar, tier: p.tier });
  const link = (a, b) => S.links.find(l => l.player === a && l.other === b);
  const friends = (a, b) => link(a, b)?.status === 'friends' && link(b, a)?.status === 'friends';
  function me(body) {
    const pid = body?.p_id; if (!pid) return null;
    if (!S.players[pid]) S.players[pid] = { id: pid, name: body.p_name || 'You', avatar: null, tier: 'Bronze', score: 0, rating: 0, streak: 0, xp: 0, level: 1, last_played: null, friend_code: null, created: now(), bot: false, pz_placed: 0, pz_done: 0 };
    S.me = pid; return S.players[pid];
  }
  function bot(name) {
    const n = Object.values(S.players).filter(p => p.bot).length, pid = id();
    const lvl = 5 + Math.floor(Math.random() * 120);
    S.players[pid] = { id: pid, name: name || BOT_NAMES[n % BOT_NAMES.length] + (n >= BOT_NAMES.length ? ` ${n}` : ''), avatar: BOT_AVATARS[n % BOT_AVATARS.length], tier: 'Silver', score: 200 + Math.floor(Math.random() * 600), rating: 250, streak: Math.floor(Math.random() * 9), xp: lvl * 40, level: lvl, last_played: now() - 3600e3 * (1 + Math.random() * 30), friend_code: null, created: now(), bot: true, pz_placed: 0, pz_done: 0 };
    return S.players[pid];
  }
  const codeOf = p => p.friend_code ??= Array.from({ length: 6 }, () => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 31)]).join('');
  const setLink = (a, b, status, extra = {}) => { let l = link(a, b); if (!l) { l = { player: a, other: b, created: now() }; S.links.push(l) } Object.assign(l, { status }, extra); return l };
  const dropLinks = (a, b) => { S.links = S.links.filter(l => !(l.player === a && l.other === b || l.player === b && l.other === a)) };

  // ---- shared puzzles (duo_*), mirroring leaderboard.sql ----
  const open = pid => S.duos.filter(d => (d.a === pid && ['pending', 'active'].includes(d.status)) || (d.b === pid && d.status === 'active')).length;
  const claimedBy = (d, pid) => d.a === pid ? d.a_claimed : d.b_claimed;
  const seenBy = (d, pid) => (d.a === pid ? d.a_seen : d.b_seen) ?? d.created;
  const piecesOf = d => S.pieces.filter(x => x.duo === d.id);
  const partnerOf = (d, pid) => P(d.a === pid ? d.b : d.a);
  const current = pid => S.duos.filter(d => (d.a === pid || d.b === pid) && (['pending', 'active'].includes(d.status) || d.status === 'done' && (!claimedBy(d, pid) || d.done > now() - 3 * 864e5)))
    .sort((x, y) => (['pending', 'active'].includes(y.status) - ['pending', 'active'].includes(x.status)) || y.created - x.created)[0];
  const activity = pid => S.duos.filter(d => (d.a === pid || d.b === pid) && (d.status === 'active' || d.status === 'done' && !claimedBy(d, pid))).map(d => {
    const o = partnerOf(d, pid), seen = seenBy(d, pid), ps = piecesOf(d);
    return { id: d.id, name: o.name, found: ps.filter(x => x.found_by === o.id && x.found > seen).length, placed: ps.filter(x => x.placed_by === o.id && x.placed > seen).length, done: d.status === 'done' && !claimedBy(d, pid), created: d.created };
  });
  function duoState(pid, want) {
    let d = want != null ? S.duos.find(x => x.id === want && (x.a === pid || x.b === pid) && x.status !== 'left') : null;
    d ??= current(pid);
    const o = d && partnerOf(d, pid);
    const list = S.duos.filter(y => (y.a === pid && ['pending', 'active'].includes(y.status)) || (y.b === pid && y.status === 'active') || ((y.a === pid || y.b === pid) && y.status === 'done' && (!claimedBy(y, pid) || y.done > now() - 3 * 864e5)))
      .sort((x, y) => (x.status === 'done') - (y.status === 'done') || x.created - y.created).map(l => {
        const f = partnerOf(l, pid), seen = seenBy(l, pid), ps = piecesOf(l);
        return { id: l.id, art: l.art, status: l.status, mine: l.a === pid, partner: mini(f), placed: ps.filter(x => x.placed_by).length,
          news: ps.filter(x => x.found_by === f.id && x.found > seen || x.placed_by === f.id && x.placed > seen).length + (l.status === 'done' && !claimedBy(l, pid) ? 1 : 0) };
      });
    const out = {
      duo: d ? { id: d.id, art: d.art, status: d.status, mine: d.a === pid, claimed: claimedBy(d, pid), partner: mini(o) } : null,
      pieces: d ? piecesOf(d).sort((x, y) => x.piece - y.piece).map(x => ({ piece: x.piece, found_by: x.found_by, placed: !!x.placed_by, placed_by: x.placed_by })) : [],
      invites: S.duos.filter(i => i.b === pid && i.status === 'pending').sort((x, y) => y.created - x.created).map(i => ({ id: i.id, art: i.art, from: mini(P(i.a)) })),
      duos: list };
    if (d) { if (d.a === pid) d.a_seen = now(); else d.b_seen = now() }
    return out;
  }
  function duoPick(pid, level) {
    const p = P(pid); if (!p || level < 1 || level > p.level) return null;
    if (S.pieces.some(x => x.found_by === pid && x.level === level && S.duos.find(d => d.id === x.duo)?.status === 'active')) return null;
    if (S.pieces.filter(x => x.found_by === pid && x.found > now() - 864e5).length >= 6) return null;
    const cands = S.duos.filter(y => (y.a === pid || y.b === pid) && y.status === 'active' && piecesOf(y).length < 12); if (!cands.length) return null;
    const d = cands[Math.floor(Math.random() * cands.length)], free = [...Array(12).keys()].filter(g => !piecesOf(d).some(x => x.piece === g));
    if (!free.length) return null;
    const piece = free[Math.floor(Math.random() * free.length)];
    S.pieces.push({ duo: d.id, piece, found_by: pid, level, found: now(), placed_by: null, placed: null });
    return { duo: d.id, art: d.art, piece, partner: mini(partnerOf(d, pid)) };
  }
  function duoPlace(pid, duoId, piece) {
    const d = S.duos.find(x => x.id === duoId && (x.a === pid || x.b === pid) && x.status === 'active');
    if (!d) return { placed: false, done: false };
    // "Simultaneous final placing": the partner's last loose piece lands in the same instant (with the row lock, both count).
    if (S.race) { S.race = false; const o = partnerOf(d, pid), loose = piecesOf(d).find(x => !x.placed_by && x.piece !== piece); if (loose) { loose.placed_by = o.id; loose.placed = now(); log(`${o.name} placed piece ${loose.piece} at the same moment`) } }
    const x = piecesOf(d).find(y => y.piece === piece && !y.placed_by); if (x) { x.placed_by = pid; x.placed = now() }
    if (piecesOf(d).filter(y => y.placed_by).length >= 12) { d.status = 'done'; d.done = now(); return { placed: true, done: true } }
    return { placed: true, done: false };
  }

  // ---- tournaments (tourney_*): five days, points from snapshots so nothing counts twice ----
  const T_DAYS = 5, T_MAX = 8, T_OPEN_MAX = 3, PTS = { level: 10, piece: 3, puzzle: 25 };
  const tMembers = t => S.members.filter(m => m.t === t.id);
  const tStatus = t => now() >= t.ends ? 'finished' : 'live';
  function tPoints(m) {
    const p = P(m.player), t = S.tourneys.find(x => x.id === m.t), until = Math.min(now(), t.ends);
    if (m.status !== 'joined') return { levels: 0, pieces: 0, puzzles: 0, points: 0 };
    // Bots: their progress is whatever the lab gave them (m.botLevels etc.); you: totals minus the snapshot taken when you joined.
    // Counted totals are frozen at the deadline (m.final), so late syncs after the end don't move the result.
    const f = m.final || { level: p.level, pz_placed: p.pz_placed, pz_done: p.pz_done };
    const shared = S.pieces.filter(x => x.placed_by === p.id && x.placed >= m.joined && x.placed <= until).length;
    const levels = Math.max(0, Math.min(f.level - m.base_level, 60 * T_DAYS)), pieces = Math.max(0, f.pz_placed - m.base_placed) + shared, puzzles = Math.max(0, f.pz_done - m.base_done);
    return { levels, pieces, puzzles, points: levels * PTS.level + pieces * PTS.piece + puzzles * PTS.puzzle };
  }
  function tFreeze(t) { if (tStatus(t) !== 'finished') return; for (const m of tMembers(t)) if (m.status === 'joined' && !m.final) { const p = P(m.player); m.final = { level: p.level, pz_placed: p.pz_placed, pz_done: p.pz_done } } }
  function tView(t, pid) {
    tFreeze(t);
    const ms = tMembers(t), standings = ms.filter(m => m.status === 'joined').map(m => ({ ...mini(P(m.player)), me: m.player === pid, ...tPoints(m) }))
      .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name));
    let place = 0, last = null; standings.forEach((s, i) => { if (s.points !== last) place = i + 1; last = s.points; s.place = place });
    const mine = ms.find(m => m.player === pid);
    return { id: t.id, name: t.name, status: tStatus(t), starts_at: iso(t.starts), ends_at: iso(t.ends), now: iso(now()), host: mini(P(t.host)), my_status: mine?.status ?? null, claimed: !!mine?.claimed,
      standings, invited: ms.filter(m => m.status === 'invited').map(m => mini(P(m.player))), points: PTS };
  }
  const tMine = pid => S.tourneys.filter(t => S.members.some(m => m.t === t.id && m.player === pid && ['invited', 'joined'].includes(m.status)) && (tStatus(t) === 'live' || now() < t.ends + 7 * 864e5)).sort((a, b) => b.starts - a.starts);
  function tJoin(m) { const p = P(m.player); Object.assign(m, { status: 'joined', joined: now(), base_level: p.level, base_placed: p.pz_placed, base_done: p.pz_done }) }

  const RPC = {
    submit_score(b) { const p = me(b); Object.assign(p, { name: b.p_name || p.name, rating: b.p_rating, xp: Math.max(p.xp, b.p_xp), streak: b.p_streak, level: Math.max(p.level, b.p_level), tier: tierFor(b.p_rating), last_played: now() });
      const old = p.score; p.score = Math.round(b.p_rating * (1 + Math.min(b.p_streak, 10) / 100)); p.prev = old; return [{ rank: rankOf(p), score: p.score, tier: p.tier }] },
    submit_puzzle_stats(b) { const p = me(b); p.pz_placed = Math.max(p.pz_placed, b.p_placed | 0); p.pz_done = Math.max(p.pz_done, b.p_done | 0); return true },
    top_players(b) { return Object.values(S.players).filter(p => p.score > 0).sort((a, c) => c.score - a.score).slice(0, b?.p_limit || 50).map(p => row(p)) },
    player_rank(b) { const p = P(b.p_id); return p ? [row(p)] : [] },
    players_passed() { return [] },
    report_player() { return null },
    submit_time(b) { const p = me(b); return [{ holder: p.name, holder_id: p.id, time_ms: b.p_time_ms, beat: true, previous_holder: null, previous_ms: null }] },
    level_record() { return [] },
    set_avatar(b) { me(b).avatar = b.p_avatar; return null },
    player_profile(b) { const p = P(b.p_id); return p ? [{ ...row(p), best_streak: p.streak, best_rank: rankOf(p), records: 0, joined_at: iso(p.created) }] : [] },
    friends_home(b) { const p = me(b); codeOf(p);
      return { code: p.friend_code,
        friends: [p, ...S.links.filter(l => l.player === p.id && l.status === 'friends').map(l => P(l.other))].filter(Boolean).sort((a, c) => c.score - a.score)
          .map(f => ({ ...row(f), idle_hours: f.last_played ? Math.floor((now() - f.last_played) / 3600e3) : null, nudged: S.nudges.some(n => n.sender === p.id && n.receiver === f.id && n.at > now() - 20 * 3600e3) })),
        incoming: S.links.filter(l => l.other === p.id && l.status === 'pending').map(l => mini(P(l.player))),
        outgoing: S.links.filter(l => l.player === p.id && l.status === 'pending').map(l => mini(P(l.other))) } },
    add_friend(b) { const p = me(b), them = Object.values(S.players).find(x => x.friend_code === String(b.p_code || '').toUpperCase().replace(/[^A-Z0-9]/g, '')); return them ? request(p, them) : { status: 'no_code' } },
    add_friend_id(b) { const p = me(b), them = P(b.p_other); return them ? request(p, them) : { status: 'no_code' } },
    player_by_code(b) { const them = Object.values(S.players).find(x => x.friend_code === String(b.p_code || '').toUpperCase()); return them ? [row(them)] : [] },
    answer_friend(b) { const p = me(b), l = link(b.p_other, p.id); if (!l || l.status !== 'pending') return null; if (!b.p_accept) { dropLinks(p.id, b.p_other); return null }
      l.status = 'friends'; l.accepted = now(); setLink(p.id, b.p_other, 'friends'); return null },
    remove_friend(b) { dropLinks(me(b).id, b.p_other); return null },
    block_friend(b) { const p = me(b); dropLinks(p.id, b.p_other); setLink(p.id, b.p_other, 'blocked'); return null },
    nudge(b) { const p = me(b); if (!friends(p.id, b.p_friend)) return 'not_friends'; if (S.nudges.some(n => n.sender === p.id && n.receiver === b.p_friend && n.at > now() - 20 * 3600e3)) return 'already';
      S.nudges.push({ sender: p.id, receiver: b.p_friend, line: b.p_line, at: now(), seen: false }); return 'sent' },
    my_news(b) { const p = me(b), act = activity(p.id).filter(z => z.found + z.placed > 0 || z.done).sort((x, y) => y.done - x.done || y.created - x.created);
      const tInv = S.members.filter(m => m.player === p.id && m.status === 'invited' && tStatus(S.tourneys.find(t => t.id === m.t)) === 'live');
      const tDone = S.members.filter(m => m.player === p.id && m.status === 'joined' && !m.claimed && tStatus(S.tourneys.find(t => t.id === m.t)) === 'finished');
      const out = {
        nudges: S.nudges.filter(n => n.receiver === p.id && !n.seen && friends(p.id, n.sender)).map(n => ({ ...mini(P(n.sender)), line: n.line, at: iso(n.at) })),
        passed: [], passed_count: 0,
        accepted: S.links.filter(l => l.player === p.id && l.status === 'friends' && l.accepted && !l.accepted_seen).map(l => ({ ...mini(P(l.other)), at: iso(l.accepted) })),
        duo: act[0] ? { name: act[0].name, found: act[0].found, placed: act[0].placed, done: act[0].done } : null,
        duo_news: act.length, duo_invites: S.duos.filter(d => d.b === p.id && d.status === 'pending').length,
        request_names: S.links.filter(l => l.other === p.id && l.status === 'pending').slice(0, 3).map(l => P(l.player).name),
        requests: S.links.filter(l => l.other === p.id && l.status === 'pending').length,
        tourney: tInv.length || tDone.length ? { invites: tInv.length, finished: tDone.length, host: tInv[0] ? P(S.tourneys.find(t => t.id === tInv[0].t).host).name : null } : null };
      if (b.p_mark) { S.nudges.forEach(n => { if (n.receiver === p.id) n.seen = true }); S.links.forEach(l => { if (l.player === p.id && l.accepted) l.accepted_seen = true }) }
      return out },
    duo_state(b) { return duoState(me(b).id, b.p_duo ?? null) },
    duo_invite(b) { const p = me(b), f = b.p_friend; if (!friends(p.id, f)) return 'not_friends';
      if (S.duos.some(d => (d.a === p.id && d.b === f || d.a === f && d.b === p.id) && ['pending', 'active'].includes(d.status))) return 'busy';
      if (open(p.id) >= 5 || open(f) >= 5) return 'full';
      S.duos.push({ id: S.seq++, a: p.id, b: f, art: b.p_art || 'together-1', status: 'pending', a_claimed: false, b_claimed: false, created: now() }); return 'sent' },
    duo_answer(b) { const p = me(b), d = S.duos.find(x => x.id === b.p_duo && x.b === p.id && x.status === 'pending'); if (!d) return 'gone';
      if (!b.p_accept) { S.duos = S.duos.filter(x => x !== d); return 'declined' } if (open(p.id) >= 5) return 'full'; d.status = 'active'; return 'active' },
    duo_find(b) { const r = duoPick(me(b).id, b.p_level); return b.p_v ? r : r?.piece ?? null },
    duo_place(b) { return duoPlace(me(b).id, b.p_duo, b.p_piece) },
    duo_claim(b) { const p = me(b), d = S.duos.find(x => x.id === b.p_duo && x.status === 'done'); if (!d) return false;
      if (d.a === p.id && !d.a_claimed) { d.a_claimed = true; return true } if (d.b === p.id && !d.b_claimed) { d.b_claimed = true; return true } return false },
    duo_leave(b) { const p = me(b), d = S.duos.find(x => x.id === b.p_duo && (x.a === p.id || x.b === p.id) && ['pending', 'active'].includes(x.status)); if (d) d.status = 'left'; return null },
    // Tournaments.
    tourney_create(b) { const p = me(b), fs = (b.p_friends || []).filter(f => friends(p.id, f)).slice(0, T_MAX - 1);
      if (!fs.length) return { status: 'no_friends' };
      if (tMine(p.id).filter(t => tStatus(t) === 'live').length >= T_OPEN_MAX) return { status: 'full' };
      const t = { id: S.seq++, host: p.id, name: b.p_name || `${p.name}'s Troop Tournament`, starts: now(), ends: now() + T_DAYS * 864e5 };
      S.tourneys.push(t); const m = { t: t.id, player: p.id, status: 'invited', claimed: false }; S.members.push(m); tJoin(m);
      for (const f of fs) S.members.push({ t: t.id, player: f, status: 'invited', claimed: false });
      return { status: 'created', id: t.id } },
    tourney_answer(b) { const p = me(b), m = S.members.find(x => x.t === b.p_tourney && x.player === p.id && x.status === 'invited'), t = S.tourneys.find(x => x.id === b.p_tourney);
      if (!m || !t || tStatus(t) !== 'live') return 'gone'; if (!b.p_join) { m.status = 'declined'; return 'declined' }
      if (tMine(p.id).filter(x => tStatus(x) === 'live' && S.members.some(y => y.t === x.id && y.player === p.id && y.status === 'joined')).length >= T_OPEN_MAX) return 'full';
      tJoin(m); return 'joined' },
    tourney_leave(b) { const p = me(b), m = S.members.find(x => x.t === b.p_tourney && x.player === p.id); if (m && m.status !== 'declined') m.status = 'left'; return null },
    tourney_state(b) { const p = me(b), list = tMine(p.id); return { now: iso(now()), tourneys: list.map(t => tView(t, p.id)) } },
    tourney_claim(b) { const p = me(b), t = S.tourneys.find(x => x.id === b.p_tourney), m = t && S.members.find(x => x.t === t.id && x.player === p.id && x.status === 'joined');
      if (!m || tStatus(t) !== 'finished' || m.claimed) return { ok: false }; m.claimed = true; const v = tView(t, p.id), mine = v.standings.find(s => s.me);
      return { ok: true, place: mine?.place ?? null, winner: mine?.place === 1 && mine.points > 0, points: mine?.points ?? 0 } },
  };
  function request(p, them) {
    if (them.id === p.id) return { status: 'self' };
    if (link(p.id, them.id)?.status === 'friends') return { status: 'friends', name: them.name };
    if (link(them.id, p.id)?.status === 'pending') { setLink(them.id, p.id, 'friends', { accepted: now() }); setLink(p.id, them.id, 'friends'); return { status: 'friends', name: them.name } }
    setLink(p.id, them.id, 'pending'); return { status: 'sent', name: them.name };
  }

  async function call(fn, body) {
    if (S.slowMs) await new Promise(r => setTimeout(r, S.slowMs));
    if (S.offline) throw new Error(`${fn} lab offline`);
    if (S.fail > 0) { S.fail--; save(); log(`✗ ${fn} failed (simulated)`); throw new Error(`${fn} 500: lab simulated failure`) }
    const f = RPC[fn]; if (!f) { log(`? ${fn} not simulated`); return null }
    const out = f(body || {}); save(); if (!/^(my_news|duo_state|friends_home|tourney_state|top_players|player_rank|level_record)$/.test(fn)) log(`→ ${fn}`);
    return JSON.parse(JSON.stringify(out ?? null));
  }

  // ---- lab actions (Dev Tools › SOCIAL LAB) ----
  const myId = () => S.me || window.progress?.player?.id;
  const myFriends = () => S.links.filter(l => l.player === myId() && l.status === 'friends').map(l => P(l.other)).filter(p => p?.bot);
  const anyFriend = () => myFriends()[0] || (A.addFriend(), myFriends()[0]);
  const myDuos = st => S.duos.filter(d => (d.a === myId() || d.b === myId()) && (!st || st.includes(d.status)));
  const A = {
    addFriend() { if (!myId()) return log('pick a name and clear a level first'); const b = bot(); setLink(myId(), b.id, 'friends', { accepted: now() }); setLink(b.id, myId(), 'friends', { accepted: now() }); log(`${b.name} is now your friend`) },
    incomingRequest() { if (!myId()) return log('no player yet'); const b = bot(); setLink(b.id, myId(), 'pending'); log(`${b.name} sent you a friend request`) },
    acceptMine() { let n = 0; for (const l of S.links.filter(l => l.player === myId() && l.status === 'pending')) { l.status = 'friends'; l.accepted = now(); setLink(l.other, myId(), 'friends'); n++ } log(`${n} request(s) accepted by friends`) },
    nudgeMe() { const f = anyFriend(); if (!f) return; S.nudges.push({ sender: f.id, receiver: myId(), line: Math.floor(Math.random() * 32), at: now(), seen: false }); log(`${f.name} nudged you`) },
    inviteMe() { const f = myFriends().find(x => !S.duos.some(d => [d.a, d.b].includes(x.id) && [d.a, d.b].includes(myId()) && ['pending', 'active'].includes(d.status))) || (A.addFriend(), myFriends().at(-1)); if (!f) return;
      S.duos.push({ id: S.seq++, a: f.id, b: myId(), art: `together-${1 + Math.floor(Math.random() * 5)}`, status: 'pending', a_claimed: false, b_claimed: false, created: now() }); log(`${f.name} invited you to a shared puzzle`) },
    acceptInvites() { let n = 0; for (const d of myDuos(['pending']).filter(d => d.a === myId())) { d.status = 'active'; n++ } log(`${n} invite(s) accepted by friends`) },
    partnerFinds() { let n = 0; for (const d of myDuos(['active'])) { const o = partnerOf(d, myId()), free = [...Array(12).keys()].filter(g => !piecesOf(d).some(x => x.piece === g)); if (!free.length) continue;
      S.pieces.push({ duo: d.id, piece: free[0], found_by: o.id, level: 1, found: now(), placed_by: null, placed: null }); n++ } log(`partners found ${n} piece(s)`) },
    partnerPlaces() { let n = 0; for (const d of myDuos(['active'])) { const o = partnerOf(d, myId()), x = piecesOf(d).find(y => !y.placed_by); if (!x) continue; x.placed_by = o.id; x.placed = now(); n++;
      if (piecesOf(d).filter(y => y.placed_by).length >= 12) { d.status = 'done'; d.done = now() } } log(`partners placed ${n} piece(s)`) },
    oneLeft() { const d = myDuos(['active'])[0]; if (!d) return log('no active shared puzzle (invite + accept first)'); const o = partnerOf(d, myId());
      S.pieces = S.pieces.filter(x => x.duo !== d.id); for (let g = 0; g < 12; g++) S.pieces.push({ duo: d.id, piece: g, found_by: g % 2 ? o.id : myId(), level: g + 1, found: now(), placed_by: g < 11 ? o.id : null, placed: g < 11 ? now() : null });
      log(`${o.name}'s puzzle is 11/12: place the last piece`) },
    twoLeftRace() { const d = myDuos(['active'])[0]; if (!d) return log('no active shared puzzle'); const o = partnerOf(d, myId());
      S.pieces = S.pieces.filter(x => x.duo !== d.id); for (let g = 0; g < 12; g++) S.pieces.push({ duo: d.id, piece: g, found_by: g % 2 ? o.id : myId(), level: g + 1, found: now(), placed_by: g < 10 ? o.id : null, placed: g < 10 ? now() : null });
      S.race = true; log('10/12 placed: when you place one, your partner places the other at the same moment') },
    partnerFinishes() { const d = myDuos(['active'])[0]; if (!d) return log('no active shared puzzle'); const o = partnerOf(d, myId());
      for (let g = 0; g < 12; g++) { let x = piecesOf(d).find(y => y.piece === g); if (!x) S.pieces.push(x = { duo: d.id, piece: g, found_by: o.id, level: 1, found: now() }); if (!x.placed_by) { x.placed_by = o.id; x.placed = now() } }
      d.status = 'done'; d.done = now(); log(`${o.name} finished your shared puzzle`) },
    failNext() { S.fail = (S.fail || 0) + 1; log(`next ${S.fail} request(s) will fail`) },
    slow() { S.slowMs = S.slowMs ? 0 : 2000; log(S.slowMs ? 'responses now take 2s' : 'responses back to instant') },
    offline() { S.offline = !S.offline; log(S.offline ? 'server OFFLINE' : 'server back online') },
    // Tournaments
    tourneyInviteMe() { const host = anyFriend(); if (!host) return; const t = { id: S.seq++, host: host.id, name: `${host.name}'s Troop Tournament`, starts: now(), ends: now() + T_DAYS * 864e5 };
      S.tourneys.push(t); const hm = { t: t.id, player: host.id, status: 'invited', claimed: false }; S.members.push(hm); tJoin(hm);
      for (const f of myFriends().filter(f => f.id !== host.id).slice(0, 3)) { const m = { t: t.id, player: f.id, status: 'invited', claimed: false }; S.members.push(m); tJoin(m) }
      S.members.push({ t: t.id, player: myId(), status: 'invited', claimed: false }); log(`${host.name} invited you to a tournament`) },
    botsJoin() { let n = 0; for (const m of S.members.filter(m => P(m.player)?.bot && m.status === 'invited')) { tJoin(m); n++ } log(`${n} friend(s) joined`) },
    botsPlay() { let n = 0; for (const m of S.members.filter(m => m.status === 'joined' && P(m.player)?.bot && !m.final)) { const p = P(m.player); p.level += 1 + Math.floor(Math.random() * 4); p.pz_placed += Math.floor(Math.random() * 3); if (Math.random() < .15) p.pz_done++; n++ } log(`${n} friend(s) played some levels`) },
    tieTop() { const t = S.tourneys.filter(t => tStatus(t) === 'live').at(-1); if (!t) return log('no live tournament'); const v = tView(t, myId()), top = v.standings[0], mine = S.members.find(m => m.t === t.id && m.player === myId());
      if (!top || !mine || mine.status !== 'joined') return log('join first'); const p = P(myId()), mp = tPoints(mine).points, diff = top.points - mp; if (diff > 0 && diff % 10 === 0) { mine.base_level -= diff / 10; log('you are now tied for first') } else log('already tied/leading, or not a multiple of 10') },
  };
  function warp(ms) { localStorage.setItem(CLOCK, String((Number(localStorage.getItem(CLOCK)) || 0) + ms)); log(`time warp ${ms > 0 ? '+' : ''}${Math.round(ms / 3600e3)}h → ${new Date(now()).toLocaleString()}`) }
  function warpToEnd() { const t = S.tourneys.filter(t => tStatus(t) === 'live').at(-1); if (!t) return log('no live tournament'); warp(t.ends - now() + 60e3) }
  function resetClock() { localStorage.removeItem(CLOCK); log('clock back to real time') }
  function resetWorld() { const keep = S.players[S.me]; S = fresh(); if (keep) { S.players[keep.id] = { ...keep, score: 0, pz_placed: 0, pz_done: 0 }; S.me = keep.id } save(); log('lab server reset') }

  // ---- panel (Dev Tools › SOCIAL LAB) and the sandbox ribbon ----
  const css = document.createElement('style');
  css.textContent = `body.lab::after{content:'SOCIAL LAB · SANDBOX';position:fixed;left:50%;bottom:calc(env(safe-area-inset-bottom) + 2px);transform:translateX(-50%);z-index:99999;pointer-events:none;
    font:900 .55rem system-ui,sans-serif;letter-spacing:.14em;color:#2b0820;background:#ff9de2;border-radius:6px;padding:2px 8px;opacity:.9}
    #labPanel .lab-grid{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}#labPanel h5{margin:10px 0 2px;font:900 .6rem system-ui,sans-serif;letter-spacing:.12em;color:#ff9de2}
    #labPanel button{font:800 .62rem system-ui,sans-serif;padding:6px 8px;border-radius:8px;border:1px solid #ff9de277;background:#2b0820;color:#ffe3f6}
    #labPanel .lab-log{margin-top:8px;max-height:120px;overflow:auto;font:600 .58rem ui-monospace,monospace;color:#f7c8e8;white-space:pre-wrap}
    #labPanel .lab-clock{font:800 .62rem system-ui,sans-serif;color:#fff;margin-top:6px}`;
  document.head.append(css); document.body.classList.add('lab');
  const GROUPS = [
    ['FRIENDS', [['+ Friend', A.addFriend], ['Friend asks you', A.incomingRequest], ['Friends accept yours', A.acceptMine], ['Nudge me', A.nudgeMe]]],
    ['SHARED PUZZLES', [['Friend invites you', A.inviteMe], ['Friends accept invites', A.acceptInvites], ['Partner finds', A.partnerFinds], ['Partner places', A.partnerPlaces],
      ['1 piece left', A.oneLeft], ['Race last 2', A.twoLeftRace], ['Partner finishes', A.partnerFinishes]]],
    ['TOURNAMENTS', [['Friend invites you', A.tourneyInviteMe], ['Friends join', A.botsJoin], ['Friends play', A.botsPlay], ['Tie for 1st', A.tieTop]]],
    ['TIME', [['+1 hour', () => warp(3600e3)], ['+1 day', () => warp(864e5)], ['To tournament end', warpToEnd], ['Real time', resetClock]]],
    ['NETWORK', [['Fail next call', A.failNext], ['Slow 2s on/off', A.slow], ['Offline on/off', A.offline]]],
    ['LAB', [['Reset lab server', resetWorld], ['Reset lab save', () => { if (!confirmReset()) return; localStorage.removeItem('monkeyTrubble.lab.save.v1'); location.reload() }]]],
  ];
  // A second tap within 3s confirms (no browser dialogs: they freeze the WebView bridge).
  let armed = 0; function confirmReset() { if (Date.now() - armed < 3000) return true; armed = Date.now(); log('tap Reset lab save again to confirm'); return false }
  function render() {
    const box = document.getElementById('labPanel'); if (!box) return;
    box.replaceChildren(...GROUPS.map(([title, btns]) => { const w = document.createElement('div'); const h = document.createElement('h5'); h.textContent = title; const g = document.createElement('div'); g.className = 'lab-grid';
      for (const [label, fn] of btns) { const b = document.createElement('button'); b.textContent = label; b.onclick = () => { try { fn() } catch (e) { log(`error: ${e.message}`) } save(); window.__labPoke?.() }; g.append(b) }
      w.append(h, g); return w }));
    const c = document.createElement('div'); c.className = 'lab-clock'; c.textContent = `Lab clock: ${new Date(now()).toLocaleString()}${S.offline ? ' · OFFLINE' : ''}${S.slowMs ? ' · SLOW' : ''}${S.fail ? ` · ${S.fail} to fail` : ''}`;
    const l = document.createElement('div'); l.className = 'lab-log'; l.textContent = S.log.join('\n') || 'Lab log is empty.';
    box.append(c, l);
  }
  window.__labRender = render;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', render); else render();

  window.__lab = { call, A, warp, warpToEnd, resetClock, resetWorld, state: () => S, now, render };
})();
