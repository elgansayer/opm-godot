#!/usr/bin/env python3
"""
patch-build.py — Apply platform-specific source patches before building.

Usage:
    python3 scripts/patch-build.py --platform <linux|windows|web|macos|android>

Patches are idempotent: running them twice produces the same result.
"""

import argparse
import re
import sys
from pathlib import Path


def find_openmohaa_root() -> Path:
    """Locate the openmohaa source directory relative to the repo root."""
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    candidate = repo_root / "openmohaa"
    if candidate.is_dir():
        return candidate
    # Fallback: assume CWD is openmohaa/
    return Path(".")


def _strip_code_comments_and_strings(content: str) -> str:
    """
    Return a copy of *content* with C string literals and comments replaced by
    empty strings / spaces, so that brace counts and regex patches are not
    fooled by braces or keywords inside comments or string literals.

    Processing order: strings first (they may contain comment-like sequences),
    then line comments, then block comments.
    """
    # Replace string literals with ""  (handles \\-escaped characters inside)
    result = re.sub(r'"(?:[^"\\]|\\.)*"', '""', content)
    # Replace character literals with '' (e.g.  '{'  or  '\\n')
    result = re.sub(r"'(?:[^'\\]|\\.)'", "''", result)
    # Replace // … comments with a single space (preserves line numbers)
    result = re.sub(r'//[^\n]*', '// ', result)
    # Replace /* … */ block comments — non-greedy so each block is handled
    # separately (C does not allow nested block comments)
    result = re.sub(r'/\*.*?\*/', '/**/', result, flags=re.DOTALL)
    return result


def patch_sys_main_windows(src_root: Path) -> None:
    """
    Fix sys_main.c for MSVC (Windows) compilation under GODOT_GDEXTENSION:
      1. Add  #include <windows.h>  when _WIN32 is defined, so that HMODULE /
         LoadLibrary / FreeLibrary / GetProcAddress are visible.
      2. Cast  getenv()  return value to  char *  (MSVC rejects implicit
         const char * → char * conversion).
      3. Cast  0  to  cpuFeatures_t  when initialising the enum variable
         (MSVC requires an explicit cast from int to enum).
    """
    path = src_root / "code" / "sys" / "sys_main.c"
    if not path.exists():
        print(f"[patch] WARNING: {path} not found, skipping sys_main.c patch")
        return

    original = path.read_text(encoding="utf-8")
    content = original

    # --- 1. Add <windows.h> include (idempotent: skip if already present) ---
    windows_include = "#ifdef _WIN32\n#define WIN32_LEAN_AND_MEAN\n#include <windows.h>\n#endif"
    if "#include <windows.h>" not in content:
        # Insert before the first local include (sys_local.h / sys_loadlib.h)
        first_local = re.search(r'#include\s+"sys_local\.h"', content)
        if first_local:
            insert_pos = first_local.start()
            content = content[:insert_pos] + windows_include + "\n" + content[insert_pos:]
            print("[patch] sys_main.c: inserted #include <windows.h> guard")
        else:
            # Fallback: insert after the last system #include <…>
            last_sys_include = None
            for m in re.finditer(r'#include\s+<[^>]+>', content):
                last_sys_include = m
            if last_sys_include:
                insert_pos = last_sys_include.end() + 1
                content = content[:insert_pos] + windows_include + "\n" + content[insert_pos:]
                print("[patch] sys_main.c: inserted #include <windows.h> guard (fallback position)")
            else:
                print("[patch] WARNING: could not find insertion point for <windows.h>")
    else:
        print("[patch] sys_main.c: #include <windows.h> already present, skipping")

    # --- 2. Cast getenv() return value (const char * → char *) ---
    # Pattern: return getenv(  →  return (char *)getenv(
    # Applying this inside a comment is harmless (comment text stays valid C).
    patched, count = re.subn(
        r'\breturn\s+getenv\s*\(',
        'return (char *)getenv(',
        content
    )
    if count:
        content = patched
        print(f"[patch] sys_main.c: fixed {count} 'return getenv(...)' cast(s)")

    # --- 3. Cast enum initialisation (cpuFeatures_t var = 0 or 0x0) ---
    # MSVC requires an explicit cast from int to enum.
    # Handles literal 0 and hex 0x0 forms; applying inside a comment is safe.
    patched, count = re.subn(
        r'(cpuFeatures_t\s+\w+\s*=\s*)(0[xX]?0*)\s*;',
        r'\g<1>(cpuFeatures_t)\g<2>;',
        content
    )
    if count:
        content = patched
        print(f"[patch] sys_main.c: fixed {count} cpuFeatures_t initialisation(s)")

    if content != original:
        path.write_text(content, encoding="utf-8")
        print(f"[patch] sys_main.c: written to {path}")
    else:
        print("[patch] sys_main.c: no changes required")


def patch_godot_input_web(src_root: Path) -> None:
    """
    Fix godot_input.c for Emscripten (web) compilation.

    GCC accepts extraneous closing braces at file scope as a warning;
    Clang (used by Emscripten) treats them as hard errors.

    Strategy: count brace depth across the file (ignoring string literals and
    comments) and remove trailing unmatched  }  lines.  The Clang error
    reports the first extraneous  }  which, in the known failing file, is a
    stray brace appended at the end — so removing the last standalone  }  when
    the overall count is unbalanced is the correct minimal fix.
    """
    path = src_root / "code" / "godot" / "godot_input.c"
    if not path.exists():
        print(f"[patch] WARNING: {path} not found, skipping godot_input.c patch")
        return

    original = path.read_text(encoding="utf-8")
    stripped = _strip_code_comments_and_strings(original)

    open_count = stripped.count('{')
    close_count = stripped.count('}')
    extra = close_count - open_count

    if extra <= 0:
        print(f"[patch] godot_input.c: braces balanced "
              f"(open={open_count}, close={close_count}), no patch needed")
        return

    print(f"[patch] godot_input.c: found {extra} extra closing brace(s) "
          f"(open={open_count}, close={close_count}) — removing from end of file")

    content = original
    removed = 0
    while removed < extra:
        lines = content.rstrip('\n').split('\n')
        # Remove the last line whose stripped form is exactly '}'
        for i in range(len(lines) - 1, -1, -1):
            if re.match(r'^\s*\}\s*$', lines[i]):
                del lines[i]
                removed += 1
                print(f"[patch] godot_input.c: removed extraneous '}}' at line {i + 1}")
                break
        else:
            print("[patch] WARNING: could not find standalone '}' to remove — stopping")
            break
        content = '\n'.join(lines) + '\n'

    if content != original:
        path.write_text(content, encoding="utf-8")
        print(f"[patch] godot_input.c: written to {path}")
    else:
        print("[patch] godot_input.c: no changes made")


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply pre-build source patches")
    parser.add_argument("--platform", required=True,
                        choices=["linux", "windows", "web", "macos", "android"],
                        help="Target build platform")
    args = parser.parse_args()

    src_root = find_openmohaa_root()
    print(f"[patch] openmohaa source root: {src_root.resolve()}")
    print(f"[patch] target platform: {args.platform}")

    if args.platform == "windows":
        patch_sys_main_windows(src_root)
    elif args.platform == "web":
        patch_godot_input_web(src_root)
    else:
        print(f"[patch] no patches defined for platform '{args.platform}', nothing to do")

    return 0


if __name__ == "__main__":
    sys.exit(main())
