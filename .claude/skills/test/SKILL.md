# /test — Run headless smoke tests

Run the project's headless smoke test suite and analyze results.

## Steps

1. Run `./build.sh test` (which calls `scripts/test.sh`)
2. This launches Godot in headless mode with a 5-second timeout
3. Capture and analyze the output
4. If the test fails:
   - Check for missing GDExtension binaries in `project/bin/`
   - Check for Godot installation issues
   - Analyze error messages and suggest fixes
5. Report pass/fail status with relevant details
