/** Minimal iNaturalist API helpers shared by the photo scripts. */

export const INAT_BASE = "https://api.inaturalist.org/v1";
export const USER_AGENT = "DownUnderBirdCollector-Data/1.0 (github.com/michaelnmadani/BirdPokemon)";

/** Licences whose terms allow showing the photo in a non-commercial app with credit. */
export const DISPLAY_LICENCES = ["cc0", "cc-by", "cc-by-nc", "cc-by-sa", "cc-by-nc-sa"];

export type INatPhoto = {
  id: number;
  url: string;
  license_code?: string | null;
  attribution?: string | null;
};

export type INatObservation = {
  id: number;
  photos: INatPhoto[];
  user?: { login: string; name?: string | null } | null;
};

type INatResponse = {
  total_results: number;
  results: INatObservation[];
};

export async function observations(params: Record<string, string>): Promise<INatResponse> {
  const url = new URL(`${INAT_BASE}/observations`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const resp = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (!resp.ok) throw new Error(`iNaturalist ${resp.status} for ${url}`);
  return (await resp.json()) as INatResponse;
}

/** iNat photo URLs come as /square. (75px); swap in another size. */
export function photoSize(url: string, size: "small" | "medium" | "large" | "original"): string {
  return url.replace(/\/(square|small|medium|large|thumb)\./, `/${size}.`);
}

/** "(c) Jane Doe, some rights reserved (CC BY-NC)" -> "© Jane Doe". */
export function cleanAttribution(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const cleaned = raw
    .replace(/^\(c\)\s*/i, "© ")
    .replace(/,?\s*(some|all|no) rights reserved/i, "")
    .replace(/\s*\((CC[^)]*|public domain)\)\s*$/i, "")
    .trim();
  return cleaned || null;
}

/**
 * Credit line for a photo. CC0 photos carry only "no rights reserved" as
 * their attribution, so fall back to the observer's name.
 */
export function photoCreditFor(photo: INatPhoto, observer?: INatObservation["user"]): string | null {
  return cleanAttribution(photo.attribution) ?? (observer?.name?.trim() || observer?.login || null);
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
