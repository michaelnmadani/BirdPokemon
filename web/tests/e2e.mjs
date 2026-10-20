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

  await step('Species detail shows taxonomy and photo credit slot', async () => {
    await page.locator('.species-row', { hasText: 'Laughing Kookaburra' }).click();
    await page.getByRole('heading', { name: 'Laughing Kookaburra' }).waitFor();
    await page.getByText('Not collected yet').waitFor();
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
    await go('Map');
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
    await go('Map');
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

  await step('Settings reports offline readiness', async () => {
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
