# opencore-amr decoders (AMR-NB / AMR-WB)

The decoder half of [opencore-amr](https://sourceforge.net/projects/opencore-amr/)
0.1.6, from `opencore-amr-0.1.6.tar.gz` (SHA-256
`483eb4061088e2b34b358e47540b5d495a96cd468e361050fae615b1809dc4a1`), Apache
License 2.0 — see `LICENSE` and `NOTICE`. The code is unmodified; only the files
the decoders need were copied (encoder sources left out, `DISABLE_AMRNB_ENCODER`
set), using the source lists in the release's `amrnb/Makefile.am` and
`amrwb/Makefile.am`. `include/AMRNB.h` and `include/AMRWB.h` declare the
release's C wrapper API for Swift.

Used by `DownUnderBirdCollector/Services/AMRDecoder.swift` to read voice-recorder
files (`.amr`, or AMR inside `.3gp`), which iOS can't decode itself. The web app
uses the same decoder compiled to WebAssembly (`@audio/decode-amr`).
