/*
 * godot_vfs_accessors.c — Thin accessor functions for the engine VFS.
 *
 * MoHAARunner.cpp (C++) cannot include qcommon.h directly because of
 * header collisions with godot-cpp.  These C functions wrap the engine's
 * FS_* API and are called via extern "C" from the Godot side.
 *
 * All file I/O goes through the engine VFS — pk3 archives, search-path
 * ordering, and com_target_game selection are handled transparently.
 */

#include "../qcommon/q_shared.h"
#include "../qcommon/qcommon.h"

/*
 * Godot_VFS_ReadFile — read an entire file from the engine VFS.
 *
 * Returns the file length in bytes, or -1 if not found.
 * On success, *out_buffer points to engine-allocated memory that
 * the caller MUST free with Godot_VFS_FreeFile().
 */
long Godot_VFS_ReadFile(const char *qpath, void **out_buffer) {
    if (!qpath || !out_buffer) return -1;
    return FS_ReadFile(qpath, out_buffer);
}

/*
 * Godot_VFS_FreeFile — free memory returned by Godot_VFS_ReadFile.
 */
void Godot_VFS_FreeFile(void *buffer) {
    if (buffer) {
        FS_FreeFile(buffer);
    }
}

/*
 * Godot_VFS_FileExists — check whether a file exists in the VFS.
 * Returns 1 if found, 0 if not.
 */
int Godot_VFS_FileExists(const char *qpath) {
    if (!qpath) return 0;
    return (FS_ReadFile(qpath, NULL) >= 0) ? 1 : 0;
}

/*
 * Godot_VFS_ListFiles — list files in a VFS directory.
 *
 * Returns a NULL-terminated array of filenames.  The caller reads
 * count from *out_count and MUST call Godot_VFS_FreeFileList() when done.
 */
char **Godot_VFS_ListFiles(const char *directory, const char *extension, int *out_count) {
    if (!directory || !out_count) return NULL;
    return FS_ListFiles(directory, extension, qfalse, out_count);
}

/*
 * Godot_VFS_FreeFileList — free the array returned by Godot_VFS_ListFiles.
 */
void Godot_VFS_FreeFileList(char **list) {
    if (list) {
        FS_FreeFileList(list);
    }
}

/*
 * Godot_VFS_GetBasepath — return the current fs_basepath value.
 */
const char *Godot_VFS_GetBasepath(void) {
    cvar_t *bp = Cvar_Get("fs_basepath", "", 0);
    return bp ? bp->string : "";
}

/*
 * Godot_VFS_GetGamedir — return the current game directory name (e.g. "main").
 */
const char *Godot_VFS_GetGamedir(void) {
    return FS_Gamedir();
}
