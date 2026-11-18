# Watercolour field guide pictures

`watercolour.py` turns each species photo into a watercolour using your local
**AI Image Studio** (github.com/michaelnmadani/AI_Image_Creation). It runs on
the PC where the studio runs — the studio only listens on `127.0.0.1`.

For each bird it downloads the iNaturalist photo, queues an image-to-image job
(optionally guided by a ControlNet so the outline and markings stay accurate),
and saves:

- `DownUnderBirdCollector/Resources/Art/AU/<code>.jpg` — the painting, 640 px
- `DownUnderBirdCollector/Resources/Art/art_AU.json` — which photo each painting
  came from, its photographer and licence, and the model/seed used

Both apps pick these up automatically: the web build copies them and the iOS
project bundles the `Art` folder. Settings gets a **Watercolour / Photo**
switch, species pages credit the photo each painting is based on, and
Settings → **Photo, painting & sound credits** lists every credit.

## Run it (Windows)

1. Start AI Image Studio (desktop shortcut or `AI Image Studio.bat`).
2. In this repo, use the studio's Python (it already has Pillow):

   ```bat
   set PY=C:\path\to\AI_Image_Creation\.venv\Scripts\python.exe
   %PY% scripts\artwork\watercolour.py --list-models
   ```

3. Try a handful first, then open `scripts\artwork\review_AU.html` to compare
   photo and painting side by side:

   ```bat
   %PY% scripts\artwork\watercolour.py --checkpoint dreamshaper --controlnet canny --limit 8
   ```

4. Happy with the look? Run the rest (it skips birds already painted, and you
   can stop with Ctrl+C and re-run to carry on):

   ```bat
   %PY% scripts\artwork\watercolour.py --checkpoint dreamshaper --controlnet canny
   ```

5. Redo any that came out wrong — a different seed, or lower `--denoise` to stay
   closer to the photo:

   ```bat
   %PY% scripts\artwork\watercolour.py --checkpoint dreamshaper --controlnet canny --redo laukoo1,galah1 --seed 7
   ```

6. Commit and push the `Art` folder (about 30 MB for all 496 birds):

   ```bat
   git add DownUnderBirdCollector/Resources/Art
   git commit -m "Add watercolour pictures"
   git push
   ```

On macOS/Linux it's the same with `.venv/bin/python` and forward slashes.

## Settings that matter

| Option | Default | Notes |
| --- | --- | --- |
| `--checkpoint` | — | Name (or part of it) from `--list-models`. SD1.5 paints at 768 px, SDXL/Flux at 1024 px. |
| `--controlnet` | none | Strongly recommended: a canny ControlNet matching the checkpoint family keeps the bird anatomically right. |
| `--cn-preprocess` / `--cn-strength` | `canny` / `0.6` | `lineart` is softer; raise strength if birds drift. |
| `--denoise` | `0.5` | 0.35 ≈ photo with a paint finish, 0.65 ≈ loose painting. |
| `--lora NAME[:WEIGHT]` | none | Add a watercolour style LoRA (repeatable). |
| `--seed` | fixed | One seed for every bird keeps the style consistent. |
| `--prompt` | field-guide watercolour | `{common}`, `{scientific}` and `{a}` (a/an) are filled in per bird. |
| `--studio` / `--token` | `http://127.0.0.1:8188` | Only needed if the studio runs elsewhere. |

## Licences

Every species photo is Creative Commons (CC0, BY, BY-SA, BY-NC or BY-NC-SA —
none are "no derivatives"), so each can be adapted. A painting is an
adaptation of its photo: it is credited to the photographer and keeps the
photo's licence (required for the share-alike ones). The script records this
in `art_AU.json`; don't remove those fields.
