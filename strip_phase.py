#!/usr/bin/env python3
import re, glob, os

def strip_phase(line):
    line = re.sub(r'\s*\(Phase\s+[0-9]+[a-z]?(?:[/\u2013-][0-9]+[a-z]?)?\+?\)', '', line)
    line = re.sub(r'Phase\s+[0-9]+[a-z]?(?:[/\u2013-][0-9]+[a-z]?)?\+?\s*[:.]\s*', '', line)
    line = re.sub(r'Phase\s+[0-9]+[a-z]?(?:[/\u2013-][0-9]+[a-z]?)?\+?\s*[\u2014\u2500]+\s*', '', line)
    line = re.sub(r'Phase\s+[0-9]+[a-z]?(?:[/\u2013-][0-9]+[a-z]?)?\+?\s+', '', line)
    line = re.sub(r'  +', ' ', line)
    line = re.sub(r'\u2500\u2500\s*\u2500\u2500', '\u2500\u2500', line)
    line = re.sub(r'(//\s*)[\u2014\u2500]+\s*$', r'\1', line)
    line = line.rstrip()
    return line

def is_empty_comment_line(line):
    stripped = line.strip()
    if re.match(r'^//\s*$', stripped): return True
    if re.match(r'^/\*\s*[\u2500\u2014]*\s*\*/\s*$', stripped): return True
    if re.match(r'^\*\s*$', stripped): return True
    if re.match(r'^//\s*\u2500\u2500\s*$', stripped): return True
    return False

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    new_lines = []
    changed = False
    removed = 0
    modified = 0
    for line in lines:
        if re.search(r'Phase\s+[0-9]', line):
            new_line = strip_phase(line.rstrip('\n'))
            if is_empty_comment_line(new_line):
                removed += 1
                changed = True
                continue
            if new_line != line.rstrip('\n'):
                modified += 1
                changed = True
            new_lines.append(new_line + '\n')
        else:
            new_lines.append(line)
    if changed:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        print(f"  {filepath}: {modified} modified, {removed} removed")
    return modified + removed

base = 'openmohaa/code/godot'
total = 0
for ext in ('*.c', '*.cpp', '*.h'):
    for filepath in sorted(glob.glob(os.path.join(base, ext))):
        count = process_file(filepath)
        total += count
print(f"\nTotal changes: {total}")
