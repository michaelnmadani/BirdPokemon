// End-to-end check of the built web app in headless Chromium:
// browse, capture two sightings (EXIF location + live GPS), view them,
// then go offline, reload, and make sure everything still works.
//
//   npm run e2e            (builds first)
//   SCREENSHOTS=1 npm run e2e   also saves screenshots to web/test-results/
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixture = (name) => resolve(root, 'tests/fixtures', name);
const port = 5000 + Math.floor(Math.random() * 1000);
const base = `http://127.0.0.1:${port}/`;
const shots = process.env.SCREENSHOTS ? resolve(root, 'test-results') : null;
if (shots) mkdirSync(shots, { recursive: true });

const server = spawn(process.execPath, [resolve(root, 'scripts/serve.mjs')], {
  env: { ...process.env, PORT: String(port) },
  stdio: ['ignore', 'pipe', 'inherit'],
});
await new Promise((ok) => server.stdout.once('data', ok));

const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
const context = await browser.newContext({
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 2,
  isMobile: true,
  hasTouch: true,
  permissions: ['geolocation'],
  geolocation: { latitude: -33.8688, longitude: 151.2093, accuracy: 12 },
  locale: 'en-AU',
  timezoneId: 'Australia/Brisbane',
});
// Give the Laughing Kookaburra a call recording (served from a local fixture).
await context.route('**/data/taxonomy_AU.json', async (route) => {
  const resp = await route.fetch();
  const species = await resp.json();
  const kooka = species.find((s) => s.ebirdCode === 'laukoo1');
  Object.assign(kooka, { callURL: 'https://calls.test/laukoo1.wav', callAttribution: '© Test Recordist', callLicense: 'cc-by-nc', callSource: 'xeno-canto', callPageURL: 'https://xeno-canto.org/1' });
  await route.fulfill({ response: resp, json: species });
});
await context.route('https://calls.test/**', (route) => route.fulfill({ path: fixture('call.wav'), contentType: 'audio/wav' }));
const page = await context.newPage();
page.setDefaultTimeout(20000);
const errors = [];
page.on('pageerror', (err) => errors.push(err.message));
page.on('console', (msg) => {
  // Tiles and remote photos may legitimately fail (sandboxed CI, offline step).
  if (msg.type() === 'error' && !/Failed to load resource|ERR_INTERNET_DISCONNECTED|net::/.test(msg.text())) errors.push(msg.text());
});

const tab = (name) => page.locator('#tabbar').getByRole('link', { name, exact: true });
// Switch tabs and wait for the new screen, so later lookups can't hit the old one.
const go = async (name) => {
  await tab(name).click();
  await page.locator('h1', { hasText: name === 'Capture' ? /Capture|Which bird|Save sighting/ : name }).waitFor();
};

const openMap = async () => {
  await go('Sightings');
  await page.locator('header').getByRole('link', { name: 'Map', exact: true }).click();
  await page.locator('h1', { hasText: 'Map' }).waitFor();
};

const step = async (name, fn) => {
  process.stdout.write(`• ${name} … `);
  await fn();
  if (shots) await page.screenshot({ path: `${shots}/${name.replace(/\W+/g, '-').toLowerCase()}.png` });
  console.log('ok');
};

try {
  await step('Collection loads the Australian list', async () => {
    await page.goto(base);
    await page.getByText(/0 of 500 collected/).waitFor();
    assert.equal(await page.locator('.card').count(), 500);
  });

  await step('Field guide search', async () => {
    await go('Field Guide');
    await page.getByRole('searchbox').fill('kookaburra');
    await page.waitForFunction(() => document.querySelectorAll('.species-row').length >= 2);
    const names = await page.locator('.species-row strong').allTextContents();
    assert.ok(names.every((n) => /kookaburra/i.test(n)), names.join());
  });

  await step('Browse bird groups and genera', async () => {
    await page.getByRole('searchbox').fill('');
    await page.locator('.group-chip', { hasText: 'Flightless birds' }).click();
    await page.getByRole('heading', { name: /Flightless birds/ }).waitFor();
    const flightless = await page.locator('.rows .species-row strong').allTextContents();
    assert.deepEqual(flightless.sort(), ['Emu', 'Little Penguin', 'Southern Cassowary']);
    await go('Field Guide');
    await page.getByRole('searchbox').fill('rosel');
    await page.locator('.group-row', { hasText: 'Rosellas' }).click();
    await page.getByText('Genus Platycercus').first().waitFor();
    await page.locator('.species-row', { hasText: 'Crimson Rosella' }).waitFor();
    await go('Field Guide');
    await page.getByRole('searchbox').fill('kookaburra');
  });

  await step('Species detail shows taxonomy and photo credit slot', async () => {
    await page.locator('.species-row', { hasText: 'Laughing Kookaburra' }).click();
    await page.getByRole('heading', { name: 'Laughing Kookaburra' }).waitFor();
    await page.getByText('Not collected yet').waitFor();
  });

  await step('Hear its call plays the recording', async () => {
    await page.getByText('Recording: © Test Recordist · CC BY-NC via xeno-canto').waitFor();
    await page.getByRole('button', { name: /Hear the call of the Laughing Kookaburra/ }).click();
    await page.waitForFunction(() => {
      const audio = document.querySelector('.call-player audio');
      return audio && !audio.paused && audio.currentTime > 0;
    });
    await page.getByRole('button', { name: /Hear the call/ }).click();
    await page.waitForFunction(() => document.querySelector('.call-player audio').paused);
  });

  await step('Capture from library uses the photo location', async () => {
    await go('Capture');
    await page.locator('#library-input').setInputFiles(fixture('bird-with-gps.jpg'));
    await page.getByRole('heading', { name: 'Which bird?' }).waitFor();
    await page.getByRole('searchbox').fill('laughing');
    await page.locator('.species-row', { hasText: 'Laughing Kookaburra' }).click();
    await page.getByText('New for your collection!').waitFor();
    await page.getByText('-27.46980, 153.02510').waitFor();
    await page.getByText('from the photo').waitFor();
    await page.getByLabel('Notes').fill('Laughing on the fence at dawn');
  });

  await step('Save celebrates a new species', async () => {
    await page.getByRole('button', { name: 'Save sighting' }).click();
    await page.getByText('New species collected!').waitFor();
    await page.getByRole('button', { name: 'Nice!' }).click();
    await page.getByText(/1 of 500 Australia species collected/).waitFor();
  });

  await step('Camera capture uses live GPS', async () => {
    await page.locator('#camera-input').setInputFiles(fixture('bird-no-metadata.jpg'));
    await page.getByRole('searchbox').fill('galah');
    await page.locator('.species-row', { hasText: 'Galah' }).first().click();
    await page.getByText('-33.86880, 151.20930').waitFor();
    await page.getByText(/your location, ±12 m/).waitFor();
    await page.getByRole('button', { name: 'Save sighting' }).click();
    await page.getByRole('button', { name: 'Nice!' }).click();
  });

  await step('Collection and sightings update', async () => {
    await go('Collection');
    await page.getByText(/2 of 500 collected/).waitFor();
    await page.getByRole('tab', { name: 'Collected' }).click();
    assert.equal(await page.locator('.card.collected').count(), 2);
    await go('Sightings');
    await page.getByRole('heading', { name: 'Sightings' }).waitFor();
    assert.equal(await page.locator('.rows .species-row').count(), 2);
  });

  await step('Sighting detail shows notes and map', async () => {
    await page.locator('.species-row', { hasText: 'Laughing Kookaburra' }).click();
    await page.getByText('Laughing on the fence at dawn').waitFor();
    await page.locator('.minimap .leaflet-marker-icon').waitFor();
  });

  await step('Map pins both sightings', async () => {
    await openMap();
    await page.waitForFunction(() => document.querySelectorAll('.bigmap .leaflet-marker-icon').length === 2);
  });

  await step('Works offline after first visit', async () => {
    await page.waitForFunction(() => navigator.serviceWorker.getRegistration().then((r) => !!r?.active));
    await page.reload();
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    await context.setOffline(true);
    await page.goto(`${base}#/collection`);
    await page.getByText(/2 of 500 collected/).waitFor();
    await go('Field Guide');
    await page.getByRole('searchbox').fill('emu');
    await page.locator('.species-row', { hasText: 'Emu' }).first().waitFor();
    await openMap();
    await page.locator('.bigmap .leaflet-marker-icon').first().waitFor();
    await context.setOffline(false);
  });

  await step('Delete a sighting', async () => {
    await go('Sightings');
    await page.locator('.species-row', { hasText: 'Galah' }).click();
    await page.getByRole('button', { name: 'Delete sighting' }).click();
    await page.locator('dialog').getByRole('button', { name: 'Delete' }).click();
    await page.getByText('1 total').waitFor();
    await go('Collection');
    await page.getByText(/1 of 500 collected/).waitFor();
  });

  await step('Log a sighting without a photo at the current location', async () => {
    await go('Capture');
    await page.getByRole('button', { name: 'Log without a photo' }).click();
    await page.getByText('Choose the species you saw or heard.').waitFor();
    await page.getByRole('searchbox').fill('emu');
    await page.locator('.species-row', { hasText: 'Emu' }).first().click();
    await page.getByText('-33.86880, 151.20930').waitFor();
    await page.getByText('Logged without a photo').waitFor();
    assert.ok(await page.getByLabel('When').inputValue());
    await page.getByRole('button', { name: 'Save sighting' }).click();
    await page.getByText('New species collected!').waitFor();
    await page.getByRole('button', { name: 'Nice!' }).click();
    await go('Sightings');
    await page.locator('.species-row', { hasText: 'Emu' }).click();
    await page.getByText('Logged without a photo — field guide picture shown.').waitFor();
    await page.locator('.minimap .leaflet-marker-icon').waitFor();
    await go('Collection');
    await page.getByText(/2 of 500 collected/).waitFor();
  });

  await step('Nearby shows your sightings within 5 km', async () => {
    await go('Nearby');
    await page.getByText(/1 species spotted within 5 km/).waitFor();
    await page.locator('.species-row', { hasText: 'Emu' }).getByText('You: 1 sighting').waitFor();
    assert.equal(await page.locator('.species-row', { hasText: 'Laughing Kookaburra' }).count(), 0, 'Brisbane sighting is far away');
    await page.getByText('Add a free eBird API key').waitFor();
  });

  await step('Nearby adds recent eBird reports once a key is set', async () => {
    let requestedUrl = '';
    await context.route('https://api.ebird.org/**', (route) => {
      requestedUrl = route.request().url();
      route.fulfill({
        contentType: 'application/json',
        headers: { 'access-control-allow-origin': '*' },
        body: JSON.stringify([
          { speciesCode: 'rainbowlor1', comName: 'Rainbow Lorikeet', sciName: 'Trichoglossus moluccanus', locName: 'Hyde Park', obsDt: '2026-10-18 08:15', howMany: 12, lat: -33.873, lng: 151.211 },
          { speciesCode: 'auwhib1', comName: 'Australian White Ibis', sciName: 'Threskiornis molucca', locName: 'The Domain', obsDt: '2026-10-19 16:40', howMany: 3, lat: -33.866, lng: 151.216 },
          { speciesCode: 'emu1', comName: 'Emu', sciName: 'Dromaius novaehollandiae', locName: 'Somewhere', obsDt: '2026-10-01', lat: -33.87, lng: 151.2 },
          { speciesCode: 'mysbir1', comName: 'Mystery Bird', sciName: 'Avis incognita', locName: 'Botanic Garden', obsDt: '2026-10-17 07:00', lat: -33.864, lng: 151.217 },
          { speciesCode: 'noimin1', comName: 'Noisy Miner', sciName: 'Manorina melanocephala', locName: 'Far away', obsDt: '2026-10-19 09:00', lat: -27.47, lng: 153.02 },
        ]),
      });
    });
    await page.goto(`${base}#/settings`);
    await page.getByLabel('eBird API key').fill('test-key-123');
    await page.getByRole('button', { name: 'Save key' }).click();
    await go('Nearby');
    await page.getByText(/4 species spotted within 5 km/).waitFor();
    assert.match(requestedUrl, /dist=6/);
    assert.match(requestedUrl, /lat=-33\.87&lng=151\.21/);
    assert.match(requestedUrl, /key=test-key-123/);
    await page.locator('.species-row', { hasText: 'Rainbow Lorikeet' }).getByText(/eBird: .* · Hyde Park/).waitFor();
    await page.locator('.species-row', { hasText: 'Mystery Bird' }).getByText('Not in the field guide yet').waitFor();
    assert.equal(await page.locator('.species-row', { hasText: 'Noisy Miner' }).count(), 0, 'reports outside 5 km are dropped');
    await page.getByRole('tab', { name: 'Not collected yet' }).click();
    const missing = await page.locator('.rows .species-row strong').allTextContents();
    assert.deepEqual(missing.sort(), ['Australian White Ibis', 'Mystery Bird', 'Rainbow Lorikeet']);
    await page.locator('.nearmap .leaflet-interactive').first().waitFor();
    await context.unroute('https://api.ebird.org/**');
  });

  await step('Settings reports offline readiness', async () => {
    await go('Collection');
    await page.getByRole('link', { name: 'Settings' }).click();
    await page.getByText('Ready to use offline').waitFor();
  });

  assert.deepEqual(errors, [], `Console/page errors:\n${errors.join('\n')}`);
  console.log('\nAll end-to-end checks passed.');
} catch (err) {
  if (shots) await page.screenshot({ path: `${shots}/failure.png`, fullPage: true }).catch(() => {});
  console.error('\nFAILED:', err.message);
  if (errors.length) console.error('Page errors:', errors);
  process.exitCode = 1;
} finally {
  await browser.close();
  server.kill();
}
