/*
 * godot_ubersound.h — Ubersound / sound alias parser for the OpenMoHAA
 * GDExtension.
 *
 * MOHAA defines sound aliases in ubersound.scr and uberdialog.scr files
 * (inside pk3 archives under the sound/ directory).  An alias maps a
 * logical sound name to one or more real filenames, with optional
 * parameters (volume, distance, pitch, channel, random selection).
 *
 * This module parses those files and provides a lookup function that
 * resolves an alias to a concrete filename, handling random selection
 * from alias groups (e.g. multiple footstep variants).
 *
 * Phase 45 — Audio Completeness.
 */

#ifndef GODOT_UBERSOUND_H
#define GODOT_UBERSOUND_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Godot_Ubersound_Init — parse all ubersound .scr files from VFS.
 *
 * Scans the "ubersound/" directory for .scr files, parses each one,
 * and builds the alias lookup table.
 */
void Godot_Ubersound_Init(void);

/*
 * Godot_Ubersound_Shutdown — free all alias data.
 */
void Godot_Ubersound_Shutdown(void);

/*
 * Godot_Ubersound_Resolve — resolve a sound alias to a real filename.
 *
 * @param alias  The alias name (e.g. "snd_step_dirt").
 * @param out_path   Buffer to receive the resolved filename.
 * @param out_len    Size of the output buffer.
 * @param out_volume Receives the alias's volume override (0 = use default).
 * @param out_mindist Receives minimum distance (0 = use default).
 * @param out_maxdist Receives maximum distance (0 = use default).
 * @param out_pitch  Receives pitch override (0 = use default).
 * @param out_channel Receives the channel number (-1 = not specified).
 *
 * @return  1 if the alias was found and resolved, 0 if not.
 *          When an alias has multiple variants, one is chosen at random.
 */
int Godot_Ubersound_Resolve(const char *alias,
                            char *out_path, int out_len,
                            float *out_volume,
                            float *out_mindist,
                            float *out_maxdist,
                            float *out_pitch,
                            int   *out_channel);

/*
 * Godot_Ubersound_GetAliasCount — return the total number of aliases loaded.
 */
int Godot_Ubersound_GetAliasCount(void);

/*
 * Godot_Ubersound_IsLoaded — check whether ubersound data has been loaded.
 *
 * @return 1 if loaded, 0 if not.
 */
int Godot_Ubersound_IsLoaded(void);

/*
 * Godot_Ubersound_HasAlias — check whether a given alias exists.
 *
 * @param alias  The alias name to check.
 * @return 1 if found, 0 otherwise.
 */
int Godot_Ubersound_HasAlias(const char *alias);

#ifdef __cplusplus
}
#endif

#endif /* GODOT_UBERSOUND_H */
