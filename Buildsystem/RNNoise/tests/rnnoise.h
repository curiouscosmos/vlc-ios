/* Test double: one frame of lookahead and a deterministic 50% wet signal. */
#ifndef RD_TEST_RNNOISE_H
#define RD_TEST_RNNOISE_H
typedef struct DenoiseState DenoiseState;
DenoiseState *rnnoise_create(void *model);
void rnnoise_destroy(DenoiseState *state);
void rnnoise_reset(DenoiseState *state);
float rnnoise_process_frame(DenoiseState *state, float *out, const float *in);
#endif
