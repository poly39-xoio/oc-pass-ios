// 上傳後自動把最新 build 掛進 TestFlight 內測群組（避免每次手動補）
// 需要環境變數：ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_ID, BETA_GROUP_ID
import crypto from 'node:crypto';
import fs from 'node:fs';

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER = process.env.ASC_ISSUER_ID;
const KEY_PATH = process.env.ASC_KEY_PATH;
const APP_ID = process.env.APP_ID;
const GROUP_ID = process.env.BETA_GROUP_ID;
const EXPECTED = (process.env.EXPECTED_BUILD || '').trim(); // 這次要掛的 build 號

if (!KEY_ID || !ISSUER || !KEY_PATH || !APP_ID || !GROUP_ID) {
  console.error('missing env');
  process.exit(1);
}

function token() {
  const now = Math.floor(Date.now() / 1000);
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const data = `${enc({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })}.${enc({ iss: ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
  const key = fs.readFileSync(KEY_PATH, 'utf8');
  const sig = crypto.sign('sha256', Buffer.from(data), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${data}.${sig}`;
}

async function api(path, method = 'GET', body) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token()}`,
      'Content-Type': 'application/json',
      'User-Agent': 'ocpass-ci',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = {};
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { status: res.status, json };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let build = null;
  for (let i = 0; i < 60; i++) {
    const { status, json } = await api(`/v1/builds?filter%5Bapp%5D=${APP_ID}&limit=20&sort=-uploadedDate`);
    if (status !== 200) { console.log('list failed', status, JSON.stringify(json).slice(0, 200)); }
    const list = json.data || [];
    // 只認這一次上傳的 build 號(EXPECTED_BUILD)，避免掛到舊 build
    const cand = EXPECTED ? list.find((b) => String(b.attributes.version) === EXPECTED) : list[0];
    if (cand) {
      const state = cand.attributes.processingState;
      console.log('target build', cand.attributes.version, state);
      if (state === 'VALID') { build = cand; break; }
    } else {
      console.log('waiting for build', EXPECTED || '(newest)', 'to appear...');
    }
    await sleep(15000);
  }
  if (!build) { console.error('no VALID build found'); process.exit(1); }

  const attach = await api(`/v1/betaGroups/${GROUP_ID}/relationships/builds`, 'POST', {
    data: [{ type: 'builds', id: build.id }],
  });
  console.log('attach', attach.status, JSON.stringify(attach.json).slice(0, 200));

  const detail = await api(`/v1/builds/${build.id}/buildBetaDetail`);
  console.log('beta', JSON.stringify(detail.json?.data?.attributes || {}).slice(0, 200));
  if (attach.status >= 300) process.exit(1);
})();
