// Friends and the weekly step leaderboard.
//
// Everyone signs in with Apple. Each player uploads daily step totals keyed by
// their own local date; weeks run Sunday through Saturday in each player's time
// zone. Last week's totals stay open until Sunday noon local time so late syncs
// still count, then they freeze.

const APPLE_ISSUER = 'https://appleid.apple.com';
const INVITE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const MAX_FRIENDS = 100;
const MAX_DAILY_STEPS = 150_000;
const GRACE_HOUR = 12;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/.well-known/apple-app-site-association') return appSiteAssociation(env);
      if (url.pathname.startsWith('/i/')) return invitePage(url, env);
      if (url.pathname.startsWith('/api/v1/')) return await api(request, url, env);
      return json({ error: 'not_found' }, 404);
    } catch (error) {
      if (error instanceof HttpError) return json({ error: error.code }, error.status);
      console.error(error);
      return json({ error: 'server_error' }, 500);
    }
  },
};

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

async function api(request, url, env) {
  const route = `${request.method} ${url.pathname.slice('/api/v1'.length)}`;

  if (route === 'POST /auth/apple') return signInWithApple(await body(request), env);
  if (route === 'POST /auth/dev' && env.ALLOW_DEV_AUTH === '1') return devSignIn(await body(request), env);

  const user = await authenticate(request, env);
  switch (route) {
    case 'GET /me':
      return json({ user: publicUser(user, env) });
    case 'PATCH /me':
      return json({ user: publicUser(await updateProfile(user, await body(request), env), env) });
    case 'DELETE /me':
      await deleteAccount(user, env);
      return json({ ok: true });
    case 'POST /auth/signout':
      await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256(bearer(request))).run();
      return json({ ok: true });
    case 'PUT /steps':
      return json(await uploadSteps(user, await body(request), env));
    case 'POST /friends':
      return json(await addFriend(user, await body(request), env));
    case 'GET /leaderboard':
      return json(await leaderboard(user, env));
  }
  const removal = route.match(/^DELETE \/friends\/([\w-]{1,64})$/);
  if (removal) {
    await env.DB.batch([
      env.DB.prepare('DELETE FROM friendships WHERE user_id = ? AND friend_id = ?').bind(user.id, removal[1]),
      env.DB.prepare('DELETE FROM friendships WHERE user_id = ? AND friend_id = ?').bind(removal[1], user.id),
    ]);
    return json({ ok: true });
  }
  throw new HttpError(404, 'not_found');
}

// MARK: - Accounts

async function signInWithApple(input, env) {
  const claims = await verifyAppleIdentityToken(input.identityToken, input.nonce, env);
  let user = await env.DB.prepare('SELECT * FROM users WHERE apple_sub = ?').bind(claims.sub).first();
  if (!user) {
    user = await createUser(claims.sub, input, env);
  } else if (input.timeZone) {
    user = await updateProfile(user, { timeZone: input.timeZone }, env);
  }

  // The refresh token is only needed to revoke the Apple sign-in when the
  // account is deleted. It's skipped quietly until the Apple key is configured.
  if (input.authorizationCode && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY) {
    const refreshToken = await exchangeAppleCode(input.authorizationCode, env).catch((error) => {
      console.error('apple code exchange failed', error);
      return null;
    });
    if (refreshToken) {
      await env.DB.prepare('UPDATE users SET apple_refresh_token = ? WHERE id = ?').bind(refreshToken, user.id).run();
    }
  }

  return json({ token: await createSession(user.id, env), user: publicUser(user, env) });
}

async function devSignIn(input, env) {
  const sub = `dev-${cleanText(input.sub, 40) || 'player'}`;
  let user = await env.DB.prepare('SELECT * FROM users WHERE apple_sub = ?').bind(sub).first();
  if (!user) user = await createUser(sub, input, env);
  return json({ token: await createSession(user.id, env), user: publicUser(user, env) });
}

async function createUser(appleSub, input, env) {
  const id = crypto.randomUUID();
  const now = Date.now();
  for (let attempt = 0; attempt < 5; attempt++) {
    const inviteCode = randomInviteCode();
    const result = await env.DB.prepare(
      `INSERT INTO users (id, apple_sub, display_name, avatar_key, time_zone, invite_code, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (invite_code) DO NOTHING`,
    )
      .bind(id, appleSub, cleanName(input.displayName), cleanAvatar(input.avatarKey), cleanTimeZone(input.timeZone), inviteCode, now)
      .run();
    if (result.meta.changes === 1) {
      return env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
    }
  }
  throw new HttpError(500, 'invite_code_collision');
}

async function updateProfile(user, input, env) {
  const name = input.displayName === undefined ? user.display_name : cleanName(input.displayName);
  const avatar = input.avatarKey === undefined ? user.avatar_key : cleanAvatar(input.avatarKey);
  const timeZone = input.timeZone === undefined ? user.time_zone : cleanTimeZone(input.timeZone);
  await env.DB.prepare('UPDATE users SET display_name = ?, avatar_key = ?, time_zone = ? WHERE id = ?')
    .bind(name, avatar, timeZone, user.id)
    .run();
  return { ...user, display_name: name, avatar_key: avatar, time_zone: timeZone };
}

async function deleteAccount(user, env) {
  if (user.apple_refresh_token && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY) {
    await revokeAppleToken(user.apple_refresh_token, env).catch((error) => console.error('apple revoke failed', error));
  }
  await env.DB.batch([
    env.DB.prepare('DELETE FROM daily_steps WHERE user_id = ?').bind(user.id),
    env.DB.prepare('DELETE FROM friendships WHERE user_id = ? OR friend_id = ?').bind(user.id, user.id),
    env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(user.id),
    env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
  ]);
}

async function createSession(userId, env) {
  const token = base64url(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.prepare('INSERT INTO sessions (token_hash, user_id, created_at) VALUES (?, ?, ?)')
    .bind(await sha256(token), userId, Date.now())
    .run();
  return token;
}

async function authenticate(request, env) {
  const token = bearer(request);
  if (!token) throw new HttpError(401, 'unauthorized');
  const user = await env.DB.prepare(
    'SELECT users.* FROM sessions JOIN users ON users.id = sessions.user_id WHERE sessions.token_hash = ?',
  )
    .bind(await sha256(token))
    .first();
  if (!user) throw new HttpError(401, 'unauthorized');
  return user;
}

function publicUser(user, env) {
  return {
    id: user.id,
    displayName: user.display_name,
    avatarKey: user.avatar_key,
    timeZone: user.time_zone,
    inviteCode: user.invite_code,
    inviteURL: `https://nanobeasts.app/i/${user.invite_code}`,
  };
}

// MARK: - Steps and friends

async function uploadSteps(user, input, env) {
  const days = Array.isArray(input.days) ? input.days.slice(0, 16) : [];
  const timeZone = input.timeZone ? cleanTimeZone(input.timeZone) : user.time_zone;
  if (timeZone !== user.time_zone) {
    await env.DB.prepare('UPDATE users SET time_zone = ? WHERE id = ?').bind(timeZone, user.id).run();
  }

  const local = localNow(timeZone);
  const thisWeek = addDays(local.date, -local.weekday);
  const lastWeek = addDays(thisWeek, -7);
  const inGrace = local.weekday === 0 && local.hour < GRACE_HOUR;
  // A day ahead is allowed for a phone that has just crossed midnight.
  const latest = addDays(local.date, 1);

  // After the grace period last week is frozen, except for a player with nothing
  // in it yet (someone who joined this week): their last week fills in once, so
  // their first results show what they walked. Filling never overwrites a day.
  let backfillsLastWeek = false;
  if (!inGrace) {
    const existing = await env.DB.prepare(
      'SELECT COUNT(*) AS total FROM daily_steps WHERE user_id = ? AND day >= ? AND day < ?',
    )
      .bind(user.id, lastWeek, thisWeek)
      .first();
    backfillsLastWeek = existing.total === 0;
  }

  const now = Date.now();
  const upsert = `INSERT INTO daily_steps (user_id, day, steps, updated_at) VALUES (?, ?, ?, ?)
    ON CONFLICT (user_id, day) DO UPDATE SET steps = excluded.steps, updated_at = excluded.updated_at`;
  const insertOnly = `INSERT INTO daily_steps (user_id, day, steps, updated_at) VALUES (?, ?, ?, ?)
    ON CONFLICT (user_id, day) DO NOTHING`;
  const statements = [];
  for (const entry of days) {
    const day = typeof entry?.date === 'string' ? entry.date : '';
    const steps = Math.round(Number(entry?.steps));
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < lastWeek || day > latest) continue;
    if (!Number.isFinite(steps) || steps < 0) continue;
    const isLastWeek = day < thisWeek;
    if (isLastWeek && !inGrace && !backfillsLastWeek) continue;
    statements.push(
      env.DB.prepare(isLastWeek && !inGrace ? insertOnly : upsert).bind(user.id, day, Math.min(steps, MAX_DAILY_STEPS), now),
    );
  }
  if (statements.length) {
    statements.push(env.DB.prepare('UPDATE users SET steps_updated_at = ? WHERE id = ?').bind(now, user.id));
    await env.DB.batch(statements);
  }
  return { accepted: Math.max(statements.length - 1, 0) };
}

async function addFriend(user, input, env) {
  const code = String(input.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const friend = await env.DB.prepare('SELECT * FROM users WHERE invite_code = ?').bind(code).first();
  if (!friend) throw new HttpError(404, 'invite_not_found');
  if (friend.id === user.id) throw new HttpError(400, 'own_invite');

  const counts = await env.DB.prepare(
    'SELECT user_id, COUNT(*) AS total FROM friendships WHERE user_id IN (?, ?) GROUP BY user_id',
  )
    .bind(user.id, friend.id)
    .all();
  if (counts.results.some((row) => row.total >= MAX_FRIENDS)) throw new HttpError(400, 'friend_limit');

  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare('INSERT OR IGNORE INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?)').bind(user.id, friend.id, now),
    env.DB.prepare('INSERT OR IGNORE INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?)').bind(friend.id, user.id, now),
  ]);
  return { friend: { id: friend.id, displayName: friend.display_name, avatarKey: friend.avatar_key } };
}

async function leaderboard(user, env) {
  const people = (
    await env.DB.prepare(
      `SELECT id, display_name, avatar_key, time_zone, steps_updated_at FROM users
       WHERE id = ? OR id IN (SELECT friend_id FROM friendships WHERE user_id = ?)`,
    )
      .bind(user.id, user.id)
      .all()
  ).results;

  // Everyone's days are fetched from the earliest "last week" across time zones.
  const windows = new Map();
  let earliest = null;
  for (const person of people) {
    const local = localNow(person.time_zone);
    const weekStart = addDays(local.date, -local.weekday);
    const window = { today: local.date, weekStart, lastWeekStart: addDays(weekStart, -7) };
    windows.set(person.id, window);
    if (!earliest || window.lastWeekStart < earliest) earliest = window.lastWeekStart;
  }

  const placeholders = people.map(() => '?').join(',');
  const rows = (
    await env.DB.prepare(`SELECT user_id, day, steps FROM daily_steps WHERE day >= ? AND user_id IN (${placeholders})`)
      .bind(earliest, ...people.map((person) => person.id))
      .all()
  ).results;

  const totals = new Map(people.map((person) => [person.id, { today: 0, week: 0, lastWeek: 0, bestDay: null }]));
  for (const row of rows) {
    const window = windows.get(row.user_id);
    const total = totals.get(row.user_id);
    if (row.day > window.today) continue;
    if (row.day === window.today) total.today = row.steps;
    if (row.day >= window.weekStart) {
      total.week += row.steps;
      // Each player's biggest single day this week, for the "Best day" badge.
      if (row.steps > 0 && (!total.bestDay || row.steps > total.bestDay.steps)) {
        total.bestDay = { date: row.day, steps: row.steps };
      }
    } else if (row.day >= window.lastWeekStart) total.lastWeek += row.steps;
  }

  const mine = windows.get(user.id);
  return {
    weekStart: mine.weekStart,
    today: mine.today,
    entries: people.map((person) => ({
      id: person.id,
      displayName: person.display_name,
      avatarKey: person.avatar_key,
      isMe: person.id === user.id,
      updatedAt: person.steps_updated_at,
      ...totals.get(person.id),
    })),
  };
}

// MARK: - Sign in with Apple

let appleKeysCache = null;

async function appleSigningKey(kid) {
  if (!appleKeysCache || Date.now() - appleKeysCache.fetchedAt > 6 * 3600_000 || !appleKeysCache.keys.some((k) => k.kid === kid)) {
    const response = await fetch(`${APPLE_ISSUER}/auth/keys`);
    if (!response.ok) throw new HttpError(503, 'apple_keys_unavailable');
    appleKeysCache = { keys: (await response.json()).keys, fetchedAt: Date.now() };
  }
  const jwk = appleKeysCache.keys.find((k) => k.kid === kid);
  if (!jwk) throw new HttpError(401, 'invalid_identity_token');
  return crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
}

async function verifyAppleIdentityToken(token, nonce, env) {
  const parts = typeof token === 'string' ? token.split('.') : [];
  if (parts.length !== 3) throw new HttpError(401, 'invalid_identity_token');
  let header;
  let claims;
  try {
    header = JSON.parse(decodeText(parts[0]));
    claims = JSON.parse(decodeText(parts[1]));
  } catch {
    throw new HttpError(401, 'invalid_identity_token');
  }
  const key = await appleSigningKey(header.kid);
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64urlDecode(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  const now = Date.now() / 1000;
  if (
    !valid ||
    header.alg !== 'RS256' ||
    claims.iss !== APPLE_ISSUER ||
    claims.aud !== env.APPLE_BUNDLE_ID ||
    !claims.sub ||
    claims.exp < now
  ) {
    throw new HttpError(401, 'invalid_identity_token');
  }
  // The app hashes a fresh nonce into each request, so a captured token can't be replayed.
  if (!nonce || claims.nonce !== (await sha256Hex(nonce))) throw new HttpError(401, 'invalid_nonce');
  return claims;
}

async function appleClientSecret(env) {
  const pem = env.APPLE_PRIVATE_KEY.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const key = await crypto.subtle.importKey(
    'pkcs8',
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: env.APPLE_KEY_ID })));
  const payload = base64url(
    new TextEncoder().encode(
      JSON.stringify({ iss: env.APPLE_TEAM_ID, iat: now, exp: now + 300, aud: APPLE_ISSUER, sub: env.APPLE_BUNDLE_ID }),
    ),
  );
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

async function exchangeAppleCode(code, env) {
  const response = await fetch(`${APPLE_ISSUER}/auth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.APPLE_BUNDLE_ID,
      client_secret: await appleClientSecret(env),
      code,
      grant_type: 'authorization_code',
    }),
  });
  if (!response.ok) throw new Error(`apple token ${response.status}: ${await response.text()}`);
  return (await response.json()).refresh_token || null;
}

async function revokeAppleToken(refreshToken, env) {
  const response = await fetch(`${APPLE_ISSUER}/auth/revoke`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.APPLE_BUNDLE_ID,
      client_secret: await appleClientSecret(env),
      token: refreshToken,
      token_type_hint: 'refresh_token',
    }),
  });
  if (!response.ok) throw new Error(`apple revoke ${response.status}: ${await response.text()}`);
}

// MARK: - Invite links

function appSiteAssociation(env) {
  return json({
    applinks: {
      details: [{ appIDs: [`${env.APPLE_TEAM_ID}.${env.APPLE_BUNDLE_ID}`], components: [{ '/': '/i/*' }] }],
    },
  });
}

function invitePage(url, env) {
  const code = url.pathname.slice(3).toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Join me on Nanobeasts</title>
<meta property="og:title" content="Race me on Nanobeasts">
<meta property="og:description" content="Walk, grow your creature, and see who takes the week.">
<meta property="og:image" content="https://nanobeasts.app/assets/og.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<link rel="apple-touch-icon" sizes="180x180" href="https://nanobeasts.app/assets/apple-touch-icon.png">
<link rel="icon" type="image/png" sizes="192x192" href="https://nanobeasts.app/assets/favicon-192.png">
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#09090b;color:#fff;font-family:-apple-system,system-ui,sans-serif;text-align:center}
main{max-width:340px;padding:32px 20px}h1{font-size:26px;margin:0 0 10px}p{color:#a1a1aa;line-height:1.5;margin:0 0 24px}
.code{font:700 22px ui-monospace,Menlo,monospace;letter-spacing:4px;border:1px solid #2e2e36;border-radius:14px;padding:14px;margin:0 0 24px}
a{display:block;background:#2ee6c8;color:#04201b;font-weight:600;text-decoration:none;border-radius:14px;padding:15px;margin-bottom:12px}
small{color:#71717a}
</style></head><body><main>
<h1>Race me on Nanobeasts</h1>
<p>Install Nanobeasts, then tap this link again to join my leaderboard. Or enter this code in the app:</p>
<div class="code">${code}</div>
<a href="${env.APP_STORE_URL}">Get Nanobeasts</a>
<small>Already installed? Open the leaderboard and tap "Enter invite code".</small>
</main></body></html>`;
  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300' } });
}

// MARK: - Helpers

function localNow(timeZone) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      hourCycle: 'h23',
      weekday: 'short',
    })
      .formatToParts(new Date())
      .map((part) => [part.type, part.value]),
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    hour: Number(parts.hour),
    weekday: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(parts.weekday),
  };
}

function addDays(date, days) {
  const [year, month, day] = date.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

function cleanTimeZone(value) {
  try {
    const zone = String(value || 'UTC');
    new Intl.DateTimeFormat('en-US', { timeZone: zone });
    return zone;
  } catch {
    return 'UTC';
  }
}

function cleanText(value, limit) {
  return String(value ?? '')
    .replace(/[\p{C}]/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, limit);
}

function cleanName(value) {
  return cleanText(value, 20) || 'Researcher';
}

function cleanAvatar(value) {
  const key = String(value ?? '');
  return /^[a-z0-9-]{1,80}$/.test(key) ? key : null;
}

function randomInviteCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, (b) => INVITE_ALPHABET[b % INVITE_ALPHABET.length]).join('');
}

function bearer(request) {
  const header = request.headers.get('Authorization') || '';
  return header.startsWith('Bearer ') ? header.slice(7) : '';
}

async function body(request) {
  try {
    return (await request.json()) || {};
  } catch {
    throw new HttpError(400, 'invalid_json');
  }
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

async function sha256(text) {
  return base64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))));
}

async function sha256Hex(text) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, '0')).join('');
}

function base64url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64urlDecode(text) {
  const padded = text.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (text.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function decodeText(text) {
  return new TextDecoder().decode(base64urlDecode(text));
}
