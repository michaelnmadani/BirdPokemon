// AMR-WB decoder from opencore-amr 0.1.6 (see ../../../README.md).
#ifndef OPENCORE_AMRWB_H
#define OPENCORE_AMRWB_H
#ifdef __cplusplus
extern "C" {
#endif

/// Decodes one AMR-WB frame (storage format, starting with its TOC byte) to
/// 320 samples of 16 kHz 16-bit PCM. Pass bfi = 0.
void *D_IF_init(void);
void D_IF_exit(void *state);
void D_IF_decode(void *state, const unsigned char *bits, short *synth, int bfi);

#ifdef __cplusplus
}
#endif
#endif
