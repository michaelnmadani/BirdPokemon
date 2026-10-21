#!/usr/bin/env bash
# Download the BirdNET V2.4 sound-identification model into models/birdnet/.
#
# BirdNET (K. Lisa Yang Center for Conservation Bioacoustics at the Cornell Lab
# of Ornithology and Chemnitz University of Technology) — models licensed
# CC BY-NC-SA 4.0. The files are too big for git, so builds fetch them: the
# model is taken from the pinned birdnetlib wheel on PyPI and checked against
# known SHA-256 hashes.
#
#   scripts/birdnet/fetch-model.sh              # model + labels
#   scripts/birdnet/fetch-model.sh --example    # also BirdNET's example soundscape (for tests)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/models/birdnet"
WHEEL_VERSION="0.18.1"
WHEEL_SHA="d2283e5f747ee181b90c41b88a247ee5570152b1ad0298242bda820871d33c49"
MODEL="BirdNET_GLOBAL_6K_V2.4_Model_FP32.tflite"
MODEL_SHA="55f3e4055b1a13bfa9a2452731d0d34f6a02d6b775a334362665892794165e4c"
LABELS="BirdNET_GLOBAL_6K_V2.4_Labels.txt"
LABELS_SHA="b50b77b7c3dfe40cd637e8cccdca0173a0a4ddee8867b830ff3c1a566f477f16"
EXAMPLE_URL="https://raw.githubusercontent.com/birdnet-team/BirdNET-Analyzer/734cb1f908aca68b390dece2d72a6f2625d1a261/birdnet_analyzer/example/soundscape.wav"

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

verify() { # file expected-sha
  [[ -f "$1" && "$(sha256 "$1")" == "$2" ]]
}

mkdir -p "$OUT"
if verify "$OUT/$MODEL" "$MODEL_SHA" && verify "$OUT/$LABELS" "$LABELS_SHA"; then
  echo "BirdNET model already present in models/birdnet/"
else
  TMP="$(mktemp -d)"
  trap 'rc=$?; rm -rf "$TMP"; exit $rc' EXIT
  echo "Downloading birdnetlib $WHEEL_VERSION (contains BirdNET V2.4)…"
  python3 -m pip download --quiet --no-deps --only-binary :all: "birdnetlib==$WHEEL_VERSION" -d "$TMP"
  WHEEL="$(ls "$TMP"/birdnetlib-*.whl)"
  verify "$WHEEL" "$WHEEL_SHA" || { echo "Checksum mismatch for $WHEEL" >&2; exit 1; }
  python3 - "$WHEEL" "$OUT" "$MODEL" "$LABELS" <<'PY'
import sys, zipfile
wheel, out, *names = sys.argv[1:]
with zipfile.ZipFile(wheel) as z:
    for name in names:
        with open(f"{out}/{name}", "wb") as f:
            f.write(z.read(f"birdnetlib/models/analyzer/{name}"))
PY
  verify "$OUT/$MODEL" "$MODEL_SHA" || { echo "Checksum mismatch for $MODEL" >&2; exit 1; }
  verify "$OUT/$LABELS" "$LABELS_SHA" || { echo "Checksum mismatch for $LABELS" >&2; exit 1; }
fi

cat > "$OUT/LICENSE-BirdNET.txt" <<'TXT'
BirdNET V2.4 model and labels
K. Lisa Yang Center for Conservation Bioacoustics, Cornell Lab of Ornithology,
and Chemnitz University of Technology. https://birdnet.cornell.edu

Licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0
International (CC BY-NC-SA 4.0): https://creativecommons.org/licenses/by-nc-sa/4.0/

Kahl, S., Wood, C. M., Eibl, M., & Klinck, H. (2021). BirdNET: A deep learning
solution for avian diversity monitoring. Ecological Informatics, 61, 101236.
TXT

if [[ "${1:-}" == "--example" && ! -f "$OUT/soundscape.wav" ]]; then
  echo "Downloading BirdNET example soundscape…"
  curl -fsSL "$EXAMPLE_URL" -o "$OUT/soundscape.wav"
fi
echo "BirdNET files ready in models/birdnet/"
