/* Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Test the actual patched libvlc controls against a minimal variable store. */
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VLC_SUCCESS 0
#define unlikely(value) (value)
#define EQZ_BANDS_MAX 10
#define EQZ_BAND_VALUE_SIZE 12
typedef struct {
    char *filters;
    bool prepared, enabled, active;
} variables;
typedef struct { variables vars; } audio_output_t;
typedef struct {
    audio_output_t *aout;
    bool started;
    unsigned locks;
} player;
typedef struct { variables vars; player *player; } libvlc_media_player_t;
typedef struct { float f_preamp, f_amp[10]; } libvlc_equalizer_t;
static bool module_present = true, fail_malloc;
static unsigned chain_changes;

static void vlc_player_Lock(player *p) { assert(p->locks++ == 0); }
static void vlc_player_Unlock(player *p) { assert(--p->locks == 0); }
static bool vlc_player_IsStarted(player *p) { assert(p->locks); return p->started; }
static audio_output_t *vlc_player_aout_Hold(player *p) { assert(p->locks); return p->aout; }
static void aout_Release(audio_output_t *a) { (void)a; }
static bool module_exists(const char *name) { assert(!strcmp(name, "rnnoise")); return module_present; }
static char *var_GetString(void *obj, const char *name)
{
    assert(!strcmp(name, "audio-filter"));
    return strdup(((variables *)obj)->filters);
}
static int var_SetString(void *obj, const char *name, const char *value)
{
    if (strcmp(name, "audio-filter")) return 0;
    variables *v = obj;
    if (strcmp(v->filters, value)) ++chain_changes;
    free(v->filters);
    v->filters = strdup(value);
    return 0;
}
static bool var_GetBool(void *obj, const char *name)
{
    variables *v = obj;
    if (!strcmp(name, "rd-rnnoise-prepared")) return v->prepared;
    if (!strcmp(name, "rd-rnnoise-active")) return v->active;
    assert(!strcmp(name, "rd-rnnoise-enabled"));
    return v->enabled;
}
static int var_SetBool(void *obj, const char *name, bool value)
{
    variables *v = obj;
    if (!strcmp(name, "rd-rnnoise-prepared")) v->prepared = value;
    else { assert(!strcmp(name, "rd-rnnoise-enabled")); v->enabled = value; }
    return 0;
}
static void var_SetFloat(void *obj, const char *name, float value)
{ (void)obj; (void)name; (void)value; }
static void *test_malloc(size_t size) { return fail_malloc ? NULL : malloc(size); }
#define malloc test_malloc
#include "control_under_test.h"
#undef malloc

int main(void)
{
    audio_output_t aout = {.vars.filters = strdup("custom:equalizer2")};
    player p = {.aout = &aout};
    libvlc_media_player_t mp = {.vars.filters = strdup("custom:equalizer2"), .player = &p};
    module_present = false;
    assert(libvlc_media_player_prepare_noise_reduction(&mp) == -1);
    assert(!mp.vars.prepared && !p.locks);
    module_present = true;
    p.started = true;
    assert(libvlc_media_player_prepare_noise_reduction(&mp) == -1);
    p.started = false;
    fail_malloc = true;
    assert(libvlc_media_player_prepare_noise_reduction(&mp) == -1);
    assert(!strcmp(mp.vars.filters, "custom:equalizer2"));
    fail_malloc = false;
    assert(libvlc_media_player_prepare_noise_reduction(&mp) == 0);
    assert(!strcmp(mp.vars.filters, "custom:equalizer2:rnnoise"));
    libvlc_equalizer_t eq = {0};
    assert(libvlc_media_player_set_equalizer(&mp, &eq) == 0);
    assert(!strcmp(mp.vars.filters, "custom:equalizer2:rnnoise:equalizer"));
    assert(libvlc_media_player_set_equalizer(&mp, NULL) == 0);
    assert(!strcmp(mp.vars.filters, "custom:equalizer2:rnnoise"));
    p.started = true;
    assert(!libvlc_media_player_noise_reduction_available(&mp));
    aout.vars.active = true;
    assert(libvlc_media_player_noise_reduction_available(&mp));
    unsigned before = chain_changes;
    for (unsigned i = 0; i < 100; ++i) {
        assert(libvlc_media_player_set_noise_reduction(&mp, i % 2) == 0);
        assert(mp.vars.enabled == (bool)(i % 2));
        assert(aout.vars.enabled == mp.vars.enabled);
    }
    assert(chain_changes == before);
    p.aout = NULL;
    assert(libvlc_media_player_set_noise_reduction(&mp, false) == 0);
    assert(!mp.vars.enabled && !p.locks);
    free(mp.vars.filters);
    free(aout.vars.filters);
    return 0;
}
