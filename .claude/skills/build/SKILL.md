# /build — Build the project

Build the OpenMoHAA GDExtension for the specified platform.

## Steps

1. Ask which platform to build for if not specified: `linux`, `windows`, `macos`, `web`, or `all`
2. For web builds, ask if this should be a `--release` build
3. Run `./build.sh <target>` with appropriate flags
4. Monitor the output for errors
5. If the build fails, analyze the error output and suggest fixes
6. Report the build result — binary locations and any warnings

## Notes

- Desktop builds produce GDExtension shared libraries in `project/bin/`
- Web builds use Emscripten and output to `web/`
- The build script automatically cleans before building
- Web release builds use `./build.sh web --release`
