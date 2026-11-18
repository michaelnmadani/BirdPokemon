#!/usr/bin/env python3
"""Turn every species photo into a watercolour with your local AI Image Studio.

Runs on the computer where AI Image Studio is running (it only listens on
127.0.0.1). For each species in the bundled taxonomy it downloads the
iNaturalist photo, sends an image-to-image job (optionally guided by a
ControlNet so the bird's shape and markings stay true), and saves the result
to DownUnderBirdCollector/Resources/Art/<REGION>/<code>.jpg. Credits for every
painting (which photo it came from, the photographer and licence) go into
art_<REGION>.json next to the images, and the apps show them.

It's resumable: species already painted are skipped unless --force or --redo.

Needs Python 3.10+ and Pillow (already in AI Image Studio's environment, or
`pip install pillow`).

  python scripts/artwork/watercolour.py --list-models
  python scripts/artwork/watercolour.py --checkpoint dreamshaper --limit 5
  python scripts/artwork/watercolour.py --checkpoint dreamshaper --controlnet canny
  python scripts/artwork/watercolour.py --checkpoint dreamshaper --redo laukoo1,galah --seed 7
  python scripts/artwork/watercolour.py --review          # rebuild the review page only
"""
from __future__ import annotations

import argparse
import base64
import html
import io
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEEDS = ROOT / "DownUnderBirdCollector" / "Resources" / "Seeds"
ART = ROOT / "DownUnderBirdCollector" / "Resources" / "Art"
USER_AGENT = "DownUnderBirdCollector-Art/1.0 (github.com/michaelnmadani/BirdPokemon)"

PROMPT = ("watercolor painting of {a} {common} ({scientific}), Australian bird, natural history "
          "field guide illustration, accurate plumage colours and markings, soft washes, delicate "
          "brush strokes, visible paper texture, loose background wash")
NEGATIVE = ("photo, photograph, photorealistic, 3d render, harsh lines, text, watermark, signature, "
            "frame, border, extra limbs, extra wings, deformed, blurry")

# Long side of the generated image per model family (multiples of 64).
LONG_SIDE = {"sd15": 768, "sd2": 768, "sdxl": 1024, "flux": 1024}
SAVE_LONG_SIDE = 640  # what the apps ship: small enough to bundle 500 of them
JPEG_QUALITY = 82


# --- AI Image Studio API ---------------------------------------------------------

class Studio:
    def __init__(self, base: str, token: str | None):
        self.base = base.rstrip("/")
        self.token = token

    def _request(self, method: str, path: str, body: dict | None = None, timeout: float = 60):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        if self.token:
            req.add_header("X-Studio-Token", self.token)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return json.loads(raw) if resp.headers.get_content_type() == "application/json" else raw

    def get(self, path: str):
        return self._request("GET", path)

    def post(self, path: str, body: dict):
        return self._request("POST", path, body)

    def check(self) -> dict:
        try:
            return self.get("/api/system")
        except urllib.error.HTTPError as err:
            if err.code == 401:
                sys.exit("AI Image Studio wants an access token: pass --token (it's printed at startup).")
            raise
        except OSError as err:
            sys.exit(f"Can't reach AI Image Studio at {self.base} ({err}).\n"
                     "Start it first (AI Image Studio.bat / scripts/run.sh), then run this again.")

    def models(self, kind: str) -> list[dict]:
        return self.get(f"/api/models?type={urllib.parse.quote(kind)}")["models"]

    def run(self, graph: dict, timeout: float) -> dict:
        """Queue a graph and wait for it; returns the first output record."""
        job_id = self.post("/api/generate", {"graph": graph})["job_id"]
        deadline = time.time() + timeout
        while time.time() < deadline:
            jobs = {j["id"]: j for j in self.get("/api/queue")["jobs"]}
            job = jobs.get(job_id)
            if job and job["status"] == "completed":
                if not job["outputs"]:
                    raise RuntimeError("job finished without an image")
                return job["outputs"][0]
            if job and job["status"] in ("failed", "cancelled"):
                raise RuntimeError(job.get("error") or job["status"])
            time.sleep(1.0)
        self.post(f"/api/queue/{job_id}/cancel", {})
        raise TimeoutError(f"job {job_id} took longer than {timeout:.0f}s")

    def download(self, url: str) -> bytes:
        return self._request("GET", url, timeout=120)


def pick_model(models: list[dict], query: str | None, kind: str) -> dict | None:
    if not query:
        return None
    q = query.lower()
    exact = [m for m in models if m["id"] == query or m["name"].lower() == q]
    matches = exact or [m for m in models if q in m["name"].lower()]
    if not matches:
        names = ", ".join(m["name"] for m in models) or "none found"
        sys.exit(f"No {kind} matches '{query}'. Available: {names}")
    if len(matches) > 1:
        sys.exit(f"'{query}' matches several {kind}s: " + ", ".join(m["name"] for m in matches))
    return matches[0]


def family(model: dict) -> str:
    return model.get("effective_family") or model.get("family") or "unknown"


# --- species data ------------------------------------------------------------------

def photo_id(url: str | None) -> int | None:
    match = re.search(r"/photos/(\d+)/", url or "")
    return int(match.group(1)) if match else None


def large_photo_url(url: str) -> str:
    return re.sub(r"/(square|small|medium|thumb)\.", "/large.", url)


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def data_url(jpeg: bytes) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()


def size_for(image, long_side: int) -> tuple[int, int]:
    w, h = image.size
    scale = long_side / max(w, h)
    return max(64, round(w * scale / 64) * 64), max(64, round(h * scale / 64) * 64)


# --- graph -----------------------------------------------------------------------

def build_graph(*, checkpoint: dict, loras: list[tuple[dict, float]], controlnet: dict | None,
                cn_preprocess: str, cn_strength: float, species: dict, init: str,
                width: int, height: int, args) -> dict:
    nodes = [
        {"id": "ckpt", "type": "checkpoint_loader", "data": {"model_id": checkpoint["id"]}},
        {"id": "prompt", "type": "prompt", "data": {
            "positive": args.prompt.format(a="an" if species["commonName"][:1].lower() in "aeiou" else "a",
                                           common=species["commonName"], scientific=species["scientificName"]),
            "negative": args.negative}},
        {"id": "latent", "type": "empty_latent", "data": {"width": width, "height": height, "batch": 1}},
        {"id": "init", "type": "load_image", "data": {"role": "init", "image": init}},
        {"id": "sampler", "type": "sampler", "data": {
            "sampler": args.sampler, "steps": args.steps, "cfg": args.cfg,
            "seed": args.seed, "denoise": args.denoise}},
        {"id": "save", "type": "save_output", "data": {}},
    ]
    edges = []
    previous = "ckpt"
    for i, (lora, weight) in enumerate(loras):
        node_id = f"lora{i}"
        nodes.append({"id": node_id, "type": "lora_loader",
                      "data": {"model_id": lora["id"], "weight_unet": weight, "weight_te": weight}})
        edges.append({"from": previous, "to": node_id, "socket": "model"})
        previous = node_id
    if controlnet:
        nodes.append({"id": "control", "type": "controlnet_apply", "data": {
            "model_id": controlnet["id"], "image": init, "preprocess": cn_preprocess,
            "strength": cn_strength, "start": 0.0, "end": 0.8}})
    return {"version": 1, "nodes": nodes, "edges": edges}


# --- manifest & review page ----------------------------------------------------------

def load_manifest(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"version": 1, "style": "watercolour", "species": {}}


def save_manifest(path: Path, manifest: dict) -> None:
    manifest["species"] = dict(sorted(manifest["species"].items()))
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(path)


def write_review(region: str, species: list[dict], manifest: dict) -> Path:
    """Side-by-side page of photo and painting, to spot ones worth redoing. Lives
    next to this script (not in the app's resources, so it isn't bundled)."""
    path = Path(__file__).with_name(f"review_{region}.html")
    art_rel = Path("..", "..", ART.relative_to(ROOT)).as_posix()
    rows = []
    for s in species:
        entry = manifest["species"].get(s["ebirdCode"])
        if not entry:
            continue
        rows.append(
            f"<figure><div><img loading=lazy src='{s['thumbnailURL']}'>"
            f"<img loading=lazy src='{art_rel}/{region}/{entry['file']}'></div>"
            f"<figcaption><b>{html.escape(s['commonName'])}</b> <code>{s['ebirdCode']}</code> · seed {entry['seed']}"
            f"</figcaption></figure>")
    page = ("<!doctype html><meta charset=utf-8><title>Watercolour review</title>"
            "<style>body{font:14px system-ui;margin:16px;background:#f4f1ea}"
            "main{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:14px}"
            "figure{margin:0;background:#fff;padding:8px;border-radius:10px}"
            "figure div{display:grid;grid-template-columns:1fr 1fr;gap:6px}"
            "img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:6px}</style>"
            f"<h1>Watercolour review — {len(rows)} species</h1>"
            "<p>Photo on the left, painting on the right. Redo any with "
            "<code>--redo code1,code2</code> (try a different <code>--seed</code> or lower "
            "<code>--denoise</code> to stay closer to the photo).</p>"
            f"<main>{''.join(rows)}</main>")
    path.write_text(page, encoding="utf-8")
    return path


# --- main --------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", default="AU")
    ap.add_argument("--studio", default="http://127.0.0.1:8188", help="AI Image Studio address")
    ap.add_argument("--token", help="access token, only needed when the studio isn't on this computer")
    ap.add_argument("--list-models", action="store_true", help="show checkpoints, LoRAs and ControlNets")
    ap.add_argument("--checkpoint", help="checkpoint name (or part of it) or id")
    ap.add_argument("--lora", action="append", default=[], metavar="NAME[:WEIGHT]",
                    help="add a LoRA, e.g. a watercolour style LoRA (repeatable)")
    ap.add_argument("--controlnet", help="ControlNet name or id, keeps the bird's outline and markings")
    ap.add_argument("--cn-preprocess", default="canny", choices=["none", "canny", "lineart", "depth", "tile"])
    ap.add_argument("--cn-strength", type=float, default=0.6)
    ap.add_argument("--denoise", type=float, default=0.5,
                    help="0.3 stays close to the photo, 0.7 is more painterly (default 0.5)")
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--cfg", type=float, help="default 6 (3.5 for Flux)")
    ap.add_argument("--sampler", default="dpmpp_2m_karras")
    ap.add_argument("--seed", type=int, default=20261023, help="same seed for every bird = consistent style")
    ap.add_argument("--prompt", default=PROMPT,
                    help="use {common} and {scientific} for the bird's names, {a} for a/an")
    ap.add_argument("--negative", default=NEGATIVE)
    ap.add_argument("--limit", type=int, help="paint at most N species this run")
    ap.add_argument("--only", help="comma-separated species codes to paint (skips ones already done)")
    ap.add_argument("--redo", help="comma-separated species codes to paint again")
    ap.add_argument("--force", action="store_true", help="repaint everything")
    ap.add_argument("--timeout", type=float, default=600, help="seconds to wait for each painting")
    ap.add_argument("--review", action="store_true", help="only rebuild the review page")
    args = ap.parse_args()

    region = args.region.upper()
    species = json.loads((SEEDS / f"taxonomy_{region}.json").read_text(encoding="utf-8"))
    out_dir = ART / region
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = ART / f"art_{region}.json"
    manifest = load_manifest(manifest_path)

    if args.review:
        print(f"Review page: {write_review(region, species, manifest)}")
        return

    studio = Studio(args.studio, args.token)
    hardware = studio.check().get("hardware", {})
    print(f"Connected to AI Image Studio at {args.studio} "
          f"({hardware.get('gpu_name') or hardware.get('device', 'unknown device')})")
    if hardware.get("engine_available") is False:
        print("Warning: the studio reports its generation engine isn't installed, so jobs will fail.")

    checkpoints = studio.models("checkpoint")
    if args.list_models:
        for kind, models in (("Checkpoints", checkpoints), ("LoRAs", studio.models("lora")),
                             ("ControlNets", studio.models("controlnet"))):
            print(f"\n{kind}:")
            for m in models:
                print(f"  {m['name']:<50} {family(m):<8} id={m['id']}")
            if not models:
                print("  (none)")
        return

    checkpoint = pick_model(checkpoints, args.checkpoint, "checkpoint")
    if not checkpoint:
        sys.exit("Choose a checkpoint with --checkpoint (see --list-models).")
    fam = family(checkpoint)
    if args.cfg is None:
        args.cfg = 3.5 if fam == "flux" else 6.0
    loras = []
    lora_models = studio.models("lora") if args.lora else []
    for spec in args.lora:
        name, _, weight = spec.partition(":")
        loras.append((pick_model(lora_models, name, "LoRA"), float(weight or 0.8)))
    controlnet = pick_model(studio.models("controlnet"), args.controlnet, "ControlNet") if args.controlnet else None
    print(f"Checkpoint: {checkpoint['name']} ({fam})"
          + "".join(f", LoRA {l['name']} @ {w}" for l, w in loras)
          + (f", ControlNet {controlnet['name']} ({args.cn_preprocess})" if controlnet else ""))

    redo = {c.strip() for c in (args.redo or "").split(",") if c.strip()}
    only = {c.strip() for c in (args.only or "").split(",") if c.strip()} | redo
    unknown = only - {s["ebirdCode"] for s in species}
    if unknown:
        sys.exit(f"Unknown species code(s): {', '.join(sorted(unknown))} — codes are in taxonomy_{region}.json "
                 "(e.g. laukoo1 for Laughing Kookaburra) and on the review page.")
    todo = []
    for s in species:
        code = s["ebirdCode"]
        if not s.get("thumbnailURL") or (only and code not in only):
            continue
        done = code in manifest["species"] and (out_dir / manifest["species"][code]["file"]).exists()
        if done and not (args.force or code in redo):
            continue
        todo.append(s)
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(todo)} species to paint ({len(manifest['species'])} already done).")

    from PIL import Image  # imported late so --help works without Pillow

    long_side = LONG_SIDE.get(fam, 768)
    painted = failed = 0
    started = time.time()
    for i, s in enumerate(todo, 1):
        code = s["ebirdCode"]
        print(f"[{i}/{len(todo)}] {s['commonName']} ({code}) … ", end="", flush=True)
        try:
            source = large_photo_url(s["thumbnailURL"])
            jpeg = fetch(source)
            photo = Image.open(io.BytesIO(jpeg)).convert("RGB")
            width, height = size_for(photo, long_side)
            init = data_url(jpeg)
            graph = build_graph(checkpoint=checkpoint, loras=loras, controlnet=controlnet,
                                cn_preprocess=args.cn_preprocess, cn_strength=args.cn_strength,
                                species=s, init=init, width=width, height=height, args=args)
            output = studio.run(graph, args.timeout)
            painting = Image.open(io.BytesIO(studio.download(output["url"]))).convert("RGB")
            painting.thumbnail((SAVE_LONG_SIDE, SAVE_LONG_SIDE), Image.LANCZOS)
            file = f"{code}.jpg"
            painting.save(out_dir / file, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
            manifest["species"][code] = {
                "file": file,
                "width": painting.width,
                "height": painting.height,
                # the photo it was painted from, and its credit — the painting is a
                # derivative, so it keeps the photo's licence (required for CC BY-SA)
                "photoId": photo_id(s["thumbnailURL"]),
                "photoURL": s["thumbnailURL"],
                "photoAttribution": s.get("thumbnailAttribution"),
                "photoLicense": s.get("thumbnailLicense"),
                "license": s.get("thumbnailLicense"),
                "model": checkpoint["name"],
                "loras": [l["name"] for l, _ in loras],
                "controlnet": controlnet["name"] if controlnet else None,
                "seed": output.get("seed", args.seed),
                "denoise": args.denoise,
                "createdAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            }
            save_manifest(manifest_path, manifest)  # after every bird, so a stop loses nothing
            painted += 1
            rate = (time.time() - started) / i
            print(f"✓ {painting.width}×{painting.height}  (~{rate * (len(todo) - i) / 60:.0f} min left)")
        except KeyboardInterrupt:
            print("\nStopped — run the same command again to carry on.")
            break
        except Exception as exc:  # keep going; one bad photo shouldn't stop the batch
            failed += 1
            print(f"✗ {exc}")

    print(f"\n{painted} painted, {failed} failed. Images: {out_dir}")
    print(f"Credits: {manifest_path}")
    print(f"Review page: {write_review(region, species, manifest)}")


if __name__ == "__main__":
    main()
