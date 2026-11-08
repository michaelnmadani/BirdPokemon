// AMR-NB decoder from opencore-amr 0.1.6 (see ../../../README.md).
#ifndef OPENCORE_AMRNB_H
#define OPENCORE_AMRNB_H
#ifdef __cplusplus
extern "C" {
#endif

/// Decodes one AMR-NB frame (storage format, starting with its TOC byte) to
/// 160 samples of 8 kHz 16-bit PCM. Pass bfi = 0.
void *Decoder_Interface_init(void);
void Decoder_Interface_exit(void *state);
void Decoder_Interface_Decode(void *state, const unsigned char *in, short *out, int bfi);

#ifdef __cplusplus
}
#endif
#endif
