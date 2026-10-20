import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeColor, normalizeSpecies, bucketSize } from "./bundle.ts";
import { cleanAttribution, photoSize } from "./inat.ts";
import { parseCsv } from "./csv.ts";
import { licenceFromUrl } from "../fetch-calls.ts";

test("colour aliases fold onto the app palette", () => {
  assert.equal(normalizeColor("Rufous"), "orange");
  assert.equal(normalizeColor("grey"), "gray");
  assert.equal(normalizeColor("streaked"), null);
  assert.equal(normalizeColor("blue"), "blue");
});

test("normalizeSpecies dedupes colours and fixes unknown sizes", () => {
  const { species, warnings } = normalizeSpecies({
    ebirdCode: "x1", commonName: "X", scientificName: "X x", order: "O", family: "F",
    sizeCategory: "giant", primaryColors: ["buff", "brown", "streaked"], regionCodes: ["AU"],
  });
  assert.deepEqual(species.primaryColors, ["brown"]);
  assert.equal(species.sizeCategory, "medium");
  assert.equal(species.ebirdURL, "https://ebird.org/species/x1");
  assert.ok(warnings.some((w) => w.includes("streaked")));
});

test("size buckets match the iOS SizeCategory boundaries", () => {
  assert.equal(bucketSize(9.9), "tiny");
  assert.equal(bucketSize(10), "small");
  assert.equal(bucketSize(35), "large");
  assert.equal(bucketSize(60), "huge");
  assert.equal(bucketSize(null), null);
});

test("iNat attribution is reduced to the photographer credit", () => {
  assert.equal(cleanAttribution("(c) Jane Doe, some rights reserved (CC BY-NC)"), "© Jane Doe");
  assert.equal(cleanAttribution("Jane Doe, no rights reserved (CC0)"), "Jane Doe");
  assert.equal(cleanAttribution(null), null);
  assert.equal(photoSize("https://x/photos/1/square.jpg", "medium"), "https://x/photos/1/medium.jpg");
});

test("CSV parser handles quotes and commas", () => {
  assert.deepEqual(parseCsv('a,b\n"x, y","he said ""hi"""\r\n1,2\n'), [["a", "b"], ["x, y", 'he said "hi"'], ["1", "2"]]);
});

test("xeno-canto licence URLs map to licence codes", () => {
  assert.equal(licenceFromUrl("//creativecommons.org/licenses/by-nc-sa/4.0/"), "cc-by-nc-sa");
  assert.equal(licenceFromUrl("https://creativecommons.org/licenses/by/4.0/"), "cc-by");
  assert.equal(licenceFromUrl("//creativecommons.org/publicdomain/zero/1.0/"), "cc0");
});
