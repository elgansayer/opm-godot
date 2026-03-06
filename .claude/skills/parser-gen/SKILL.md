# /parser-gen — Generate Morfuse parser and lexer

Regenerate the Bison parser and Flex lexer for the Morfuse script engine.

## Steps

1. Check that bison and flex are installed:
   ```bash
   bison --version
   flex --version
   ```
2. Create output directory if needed:
   ```bash
   mkdir -p openmohaa/code/parser/generated
   ```
3. Run bison (parser):
   ```bash
   bison --defines="openmohaa/code/parser/generated/yyParser.hpp" \
         -o "openmohaa/code/parser/generated/yyParser.cpp" \
         openmohaa/code/parser/bison_source.txt
   ```
4. Run flex (lexer):
   ```bash
   flex -Cem --nounistd \
        -o "openmohaa/code/parser/generated/yyLexer.cpp" \
        --header-file="openmohaa/code/parser/generated/yyLexer.h" \
        openmohaa/code/parser/lex_source.txt
   ```
5. Verify output files exist and are non-empty
6. Report: generated file sizes and any warnings from bison/flex

## Notes

- This is automatically called by `build-desktop.sh` and `build-web.sh` before SCons
- Run this manually if you edit `bison_source.txt` or `lex_source.txt` and want to inspect the output
- The `--nounistd` flag is needed for cross-platform compatibility (Windows)
