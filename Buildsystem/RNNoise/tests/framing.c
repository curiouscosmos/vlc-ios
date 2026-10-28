/* Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later */
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "rnnoise.h"

struct DenoiseState { float previous[480]; };
static int live_states, fail_state = -1, fail_allocation = -1;
static void *test_calloc(size_t count, size_t size)
{
    if (fail_allocation == 0) return NULL;
    if (fail_allocation > 0) --fail_allocation;
    return calloc(count, size);
}
DenoiseState *rnnoise_create(void *model)
{
    (void)model;
    if (fail_state == 0) return NULL;
    if (fail_state > 0) --fail_state;
    DenoiseState *s = calloc(1, sizeof(*s));
    if (s) ++live_states;
    return s;
}
void rnnoise_destroy(DenoiseState *s) { --live_states; free(s); }
void rnnoise_reset(DenoiseState *s)
{
    memset(s, 0, sizeof(*s));
}
float rnnoise_process_frame(DenoiseState *s, float *out, const float *in)
{
    memcpy(out, s->previous, sizeof(s->previous));
    for (unsigned i = 0; i < 480; ++i) s->previous[i] = in[i] * .5f;
    return 1;
}
#define calloc test_calloc
#include "../native/rnnoise_frame.h"
#undef calloc

static void check(unsigned channels, bool wet, unsigned chunk)
{
    enum { frames = 6000 };
    float input[frames * 2], output[frames * 2];
    for (unsigned i = 0; i < frames; ++i)
        for (unsigned c = 0; c < channels; ++c)
            input[i * channels + c] = (c ? -1.f : 1.f) * (i % 83) / 100.f;
    memcpy(output, input, frames * channels * sizeof(float));
    rd_rnnoise state;
    assert(rd_rnnoise_init(&state, channels));
    for (unsigned i = 0; i < frames; i += chunk) {
        unsigned count = frames - i < chunk ? frames - i : chunk;
        rd_rnnoise_process(&state, output + i * channels, count, wet);
    }
    for (unsigned i = 0; i < frames; ++i)
        for (unsigned c = 0; c < channels; ++c) {
            float expected = i < RD_DELAY ? 0 : input[(i - RD_DELAY) * channels + c];
            if (wet) expected *= .5f;
            assert(fabsf(output[i * channels + c] - expected) < .00001f);
        }
    rd_rnnoise_reset(&state);
    float silence[1920] = {0};
    rd_rnnoise_process(&state, silence, RD_DELAY, wet);
    for (unsigned i = 0; i < RD_DELAY * channels; ++i) assert(silence[i] == 0);
    for (unsigned i = 0; i < 200; ++i) {
        rd_rnnoise_process(&state, silence, 1, i % 2);
        assert(state.mix >= 0 && state.mix <= 1);
    }
    rd_rnnoise_destroy(&state);
    assert(live_states == 0);
}

int main(void)
{
    for (unsigned channels = 1; channels <= 2; ++channels)
        for (unsigned chunk = 1; chunk <= 1024; chunk = chunk * 2 + 1) {
            check(channels, false, chunk);
            check(channels, true, chunk);
        }
    rd_rnnoise s;
    assert(!rd_rnnoise_init(&s, 0));
    assert(!rd_rnnoise_init(&s, 65));
    for (int i = 0; i < 2; ++i) {
        fail_state = i;
        assert(!rd_rnnoise_init(&s, 2));
        assert(live_states == 0);
    }
    fail_state = -1;
    for (int i = 0; i < 2; ++i) {
        fail_allocation = i;
        assert(!rd_rnnoise_init(&s, 2));
        assert(live_states == 0);
    }
    return 0;
}
