/* Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Fixed framing for VLC's RNNoise filter. No allocation in the audio callback.
 */
#ifndef RD_RNNOISE_FRAME_H
#define RD_RNNOISE_FRAME_H
#include <rnnoise.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#define RD_FRAME 480u
#define RD_DELAY (2u * RD_FRAME)

typedef struct {
    unsigned channels, cursor;
    float mix;
    DenoiseState **states;
    float *input, *wet, *dry;
} rd_rnnoise;

static void rd_rnnoise_destroy(rd_rnnoise *s)
{
    if (s->states)
        for (unsigned c = 0; c < s->channels; ++c)
            if (s->states[c]) rnnoise_destroy(s->states[c]);
    free(s->states);
    free(s->input);
    memset(s, 0, sizeof(*s));
}

static bool rd_rnnoise_init(rd_rnnoise *s, unsigned channels)
{
    memset(s, 0, sizeof(*s));
    if (channels == 0 || channels > 64) return false;
    s->channels = channels;
    s->states = calloc(channels, sizeof(*s->states));
    s->input = calloc(channels * (2 * RD_FRAME + RD_DELAY), sizeof(float));
    if (!s->states || !s->input) goto fail;
    s->wet = s->input + channels * RD_FRAME;
    s->dry = s->wet + channels * RD_FRAME;
    for (unsigned c = 0; c < channels; ++c) {
        s->states[c] = rnnoise_create(NULL);
        if (!s->states[c]) goto fail;
        // Initialize RNNoise's shared FFT tables before the audio callback.
        rnnoise_process_frame(s->states[c], s->wet + c * RD_FRAME, s->input + c * RD_FRAME);
        rnnoise_reset(s->states[c]);
    }
    memset(s->wet, 0, channels * RD_FRAME * sizeof(float));
    return true;
fail:
    rd_rnnoise_destroy(s);
    return false;
}

static void rd_rnnoise_reset(rd_rnnoise *s)
{
    for (unsigned c = 0; c < s->channels; ++c)
        rnnoise_reset(s->states[c]);
    memset(s->input, 0, s->channels * (2 * RD_FRAME + RD_DELAY) * sizeof(float));
    s->cursor = 0;
    s->mix = 0;
}

static void rd_rnnoise_process(rd_rnnoise *s, float *samples, unsigned frames, bool enabled)
{
    for (unsigned i = 0; i < frames; ++i) {
        unsigned frame = s->cursor % RD_FRAME;
        float target = enabled ? 1.f : 0.f;
        if (s->mix < target) s->mix += 1.f / RD_FRAME;
        else if (s->mix > target) s->mix -= 1.f / RD_FRAME;
        if (s->mix < 0) s->mix = 0;
        if (s->mix > 1) s->mix = 1;
        for (unsigned c = 0; c < s->channels; ++c) {
            unsigned sample = i * s->channels + c;
            unsigned dry = s->cursor * s->channels + c;
            unsigned channel_frame = c * RD_FRAME + frame;
            float original = samples[sample];
            // RNNoise has one frame of lookahead; buffering adds a second frame.
            samples[sample] = s->dry[dry] * (1.f - s->mix)
                + s->wet[channel_frame] * s->mix / 32768.f;
            s->dry[dry] = original;
            s->input[channel_frame] = original * 32768.f;
        }
        s->cursor = (s->cursor + 1) % RD_DELAY;
        if (s->cursor % RD_FRAME == 0)
            for (unsigned c = 0; c < s->channels; ++c)
                rnnoise_process_frame(s->states[c], s->wet + c * RD_FRAME,
                                     s->input + c * RD_FRAME);
    }
}
#endif
