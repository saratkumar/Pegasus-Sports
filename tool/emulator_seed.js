// Seeds the local Firestore emulator with a copy of production's catalog
// plus test-account invitations, for testing with
// `flutter run --dart-define=USE_EMULATOR=true` (see docs/testing-locally.md).
//
// Production is only ever READ here (GET requests). All writes go to the
// emulator at 127.0.0.1 — the target is hard-coded and the script aborts if
// the emulator isn't running.
//
// Usage (emulators already running):  node tool/emulator_seed.js

const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'fitness-booking-app-23bdc';
const PROD = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const EMULATOR = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;

// Copied as-is: what members browse and book.
const CATALOG = ['classes', 'classTypes', 'facilities', 'membershipPlans'];

// Signing in with one of these emails in the emulator's Google pop-up
// consumes the invitation and creates that account with this role/credits.
// Credits are the admin pool: usable for any class that isn't
// plan-restricted.
const TEST_ACCOUNTS = [
  { email: 'client@test.com', name: 'Test Client', role: 'client', initialCredits: 4 },
  { email: 'client2@test.com', name: 'Second Client', role: 'client', initialCredits: 1 },
  { email: 'trainer@test.com', name: 'Test Trainer', role: 'trainer', initialCredits: 0 },
  { email: 'admin@test.com', name: 'Test Admin', role: 'admin', adminLevel: 'super_admin', initialCredits: 0 },
];

// A member "imported from Glofox": a users doc with no sign-in account yet
// (importedPending). Signing in with this email must be allowed even though
// there's no invitation, and onUserCreated moves these credits onto the new
// account. Any email not listed here or in TEST_ACCOUNTS must be refused.
const IMPORTED_MEMBER = { id: 'glofox-import-1', email: 'glofox@test.com', name: 'Imported Glofox Member', phone: '91234567', credits: 3 };

// The Firebase CLI's public OAuth client, read from the installed
// firebase-tools rather than copied here.
function cliOAuthClient() {
  const { execSync } = require('child_process');
  const root = execSync('npm root -g').toString().trim();
  const api = require(path.join(root, 'firebase-tools', 'lib', 'api.js'));
  return { client_id: api.clientId(), client_secret: api.clientSecret() };
}

async function prodToken() {
  // Uses the Firebase CLI login (`firebase login`) — read access only.
  const cfg = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  const refresh = JSON.parse(fs.readFileSync(cfg, 'utf8')).tokens?.refresh_token;
  if (!refresh) throw new Error('Not logged in to the Firebase CLI — run `firebase login` first.');
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refresh,
      ...cliOAuthClient(),
    }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('Could not get a Firebase CLI token: ' + JSON.stringify(j));
  return j.access_token;
}

async function readProd(token, collection) {
  const docs = [];
  let pageToken = '';
  do {
    const url = `${PROD}/${collection}?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ''}`;
    const r = await fetch(url, { method: 'GET', headers: { authorization: `Bearer ${token}` } });
    const j = await r.json();
    if (j.error) throw new Error(`Reading ${collection}: ${j.error.message}`);
    docs.push(...(j.documents || []));
    pageToken = j.nextPageToken;
  } while (pageToken);
  return docs;
}

async function writeEmulator(collection, id, fields) {
  // "Bearer owner" is the emulator's admin token — bypasses security rules.
  const r = await fetch(`${EMULATOR}/${collection}/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { authorization: 'Bearer owner', 'content-type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!r.ok) throw new Error(`Writing ${collection}/${id}: ${r.status} ${await r.text()}`);
}

const str = (s) => ({ stringValue: s });

(async () => {
  try {
    await fetch('http://127.0.0.1:8080/');
  } catch {
    console.error('Firestore emulator is not running on 127.0.0.1:8080.\n' +
      'Start it first:  firebase emulators:start --only auth,firestore');
    process.exit(1);
  }

  const token = await prodToken();

  for (const collection of CATALOG) {
    const docs = await readProd(token, collection);
    for (const d of docs) await writeEmulator(collection, d.name.split('/').pop(), d.fields || {});
    console.log(`copied ${docs.length} ${collection}`);
  }

  // Coaches, so classes show their name/photo/description — profile fields
  // only, no contact details, plans or credits.
  const users = await readProd(token, 'users');
  const coaches = users.filter((u) => ['trainer', 'admin'].includes(u.fields?.role?.stringValue));
  for (const u of coaches) {
    const f = u.fields;
    await writeEmulator('users', u.name.split('/').pop(), {
      name: f.name || str(''),
      role: f.role,
      ...(f.coachPhotoUrl ? { coachPhotoUrl: f.coachPhotoUrl } : {}),
      ...(f.coachBio ? { coachBio: f.coachBio } : {}),
    });
  }
  console.log(`copied ${coaches.length} coach profiles (name/photo/description only)`);

  for (const a of TEST_ACCOUNTS) {
    await writeEmulator('invitations', a.email, {
      email: str(a.email),
      name: str(a.name),
      phone: str(''),
      role: str(a.role),
      ...(a.adminLevel ? { adminLevel: str(a.adminLevel) } : {}),
      initialCredits: { integerValue: String(a.initialCredits) },
    });
  }

  const m = IMPORTED_MEMBER;
  await writeEmulator('users', m.id, {
    email: str(m.email),
    name: str(m.name),
    phone: str(m.phone),
    role: str('client'),
    credits: { integerValue: String(m.credits) },
    memberships: { arrayValue: {} },
    adminPermissions: { arrayValue: {} },
    importedPending: { booleanValue: true },
    importSource: str('glofox'),
  });

  console.log('\nTest accounts — in the emulator sign-in pop-up choose "Add new account" and use:');
  for (const a of TEST_ACCOUNTS) {
    console.log(`  ${a.email.padEnd(18)} ${a.role.padEnd(8)} ${a.initialCredits} credits`);
  }
  console.log(`  ${m.email.padEnd(18)} ${'client'.padEnd(8)} ${m.credits} credits (imported from Glofox, no invitation)`);
  console.log(`  any other email    refused ("isn't registered with PSAS")`);

  // Card payments are off in test mode, so a 100%-off coupon is the way to
  // "buy" a plan locally — e.g. a junior package for a child.
  await writeEmulator('coupons', 'TESTFREE', {
    code: str('TESTFREE'),
    discountType: str('percent'),
    value: { doubleValue: 100 },
    isActive: { booleanValue: true },
    redeemedCount: { integerValue: '0' },
  });
  console.log('\nCoupon TESTFREE: 100% off any plan (card payments are off in test mode).');
  console.log('Child logins: as client@test.com add a child in My Family with a login email (e.g. kid@test.com),');
  console.log('approve the child as admin@test.com, then sign in with that email in another window.');
  console.log('\nDone. Production was only read; everything was written to the local emulator.');
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
