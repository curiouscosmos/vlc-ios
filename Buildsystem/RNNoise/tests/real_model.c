/* Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later */
#include <assert.h>
#include <math.h>
#include <string.h>
#include "../native/rnnoise_frame.h"

#ifdef RD_ALLOCATION_TEST
static int allocations, fail_at = -1;
void *rd_test_malloc(size_t size)
{
    if (fail_at == 0) return NULL;
    if (fail_at > 0) --fail_at;
    void *p = malloc(size);
    if (p) ++allocations;
    return p;
}
void *rd_test_calloc(size_t count, size_t size)
{
    if (fail_at == 0) return NULL;
    if (fail_at > 0) --fail_at;
    void *p = calloc(count, size);
    if (p) ++allocations;
    return p;
}
void rd_test_free(void *p)
{
    if (p) --allocations;
    free(p);
}
#endif

int main(void)
{
    enum { count = 4993, channels = 2 };
    float original[count * channels], whole[count * channels], chunks[count * channels];
    for (unsigned i = 0; i < count; ++i) {
        original[i * channels] = .2f * sinf(i * .03f);
        original[i * channels + 1] = .1f * cosf(i * .07f);
    }
    memcpy(whole, original, sizeof(whole));
    memcpy(chunks, original, sizeof(chunks));
    rd_rnnoise a, b;
    assert(rd_rnnoise_init(&a, channels));
    assert(rd_rnnoise_init(&b, channels));
    rd_rnnoise_process(&a, whole, count, true);
    for (unsigned i = 0; i < count;) {
        unsigned chunk = (i % 607) + 1;
        if (chunk > count - i) chunk = count - i;
        rd_rnnoise_process(&b, chunks + i * channels, chunk, true);
        i += chunk;
    }
    for (unsigned i = 0; i < count * channels; ++i) {
        assert(isfinite(whole[i]));
        assert(whole[i] == chunks[i]);
    }
    rd_rnnoise_reset(&a);
    memcpy(chunks, original, sizeof(chunks));
    rd_rnnoise_process(&a, chunks, count, true);
    for (unsigned i = 0; i < count * channels; ++i) assert(whole[i] == chunks[i]);
    rd_rnnoise_reset(&b);
    memcpy(chunks, original, sizeof(chunks));
    rd_rnnoise_process(&b, chunks, count, false);
    for (unsigned i = 0; i < count; ++i)
        for (unsigned c = 0; c < channels; ++c)
            assert(chunks[i * channels + c] ==
                   (i < RD_DELAY ? 0 : original[(i - RD_DELAY) * channels + c]));
    for (unsigned i = 0; i < 100; ++i) {
        memcpy(chunks, original, sizeof(chunks));
        rd_rnnoise_process(&b, chunks, 67, i % 2);
        for (unsigned j = 0; j < 67 * channels; ++j) assert(isfinite(chunks[j]));
    }
    rd_rnnoise_destroy(&a);
    rd_rnnoise_destroy(&b);
#ifdef RD_ALLOCATION_TEST
    assert(allocations == 0);
    for (int i = 0; i < 4; ++i) {
        fail_at = i;
        assert(rnnoise_create(NULL) == NULL);
        assert(allocations == 0);
    }
    fail_at = -1;
    DenoiseState *state = rnnoise_create(NULL);
    assert(state);
    int before = allocations;
    for (unsigned i = 0; i < 10000; ++i) rnnoise_reset(state);
    assert(allocations == before);
    rnnoise_destroy(state);
    assert(allocations == 0);
#endif
    return 0;
}
