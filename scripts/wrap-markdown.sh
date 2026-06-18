#!/usr/bin/env bash
# Hard-wraps a markdown file so no prose line exceeds WIDTH characters.
# Re-flows existing soft-wrapped paragraphs too.
# Preserves code blocks, headings, blank lines, list items, and image/link lines.
# Usage: wrap-markdown.sh [-n WIDTH] <file>

set -euo pipefail

WIDTH=95

while getopts "n:" opt; do
  case $opt in
    n) WIDTH="$OPTARG" ;;
    *) echo "Usage: $0 [-n WIDTH] <file>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [-n WIDTH] <file>" >&2
  exit 1
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
  echo "Error: file not found: $FILE" >&2
  exit 1
fi

python3 - "$FILE" "$WIDTH" <<'PYEOF'
import sys
import re
import textwrap

file_path = sys.argv[1]
width = int(sys.argv[2])

with open(file_path, "r") as f:
    lines = f.readlines()

# ── helpers ──────────────────────────────────────────────────────────────────

def is_verbatim(line):
    """Lines that must never be joined or re-wrapped."""
    s = line.rstrip("\n")
    return (
        re.match(r"^#{1,6}\s", s)          # heading
        or re.match(r"^<!--", s)           # HTML comment
        or s.strip() in ("---", "+++")     # front-matter fence
        or re.match(r"^\s*!?\[.*\]\(.*\)\s*$", s)  # standalone image/link
        or re.match(r"^\s*[-*+]\s*$", s)   # bare list bullet
    )

def list_indent(line):
    """Return (initial_indent, subsequent_indent) for a list item, or None."""
    m = re.match(r"^(\s*(?:[-*+]|\d+\.)\s+)", line)
    if m:
        ii = m.group(1)
        si = " " * len(ii)
        return ii, si
    return None

def leading_indent(line):
    m = re.match(r"^(\s+)", line)
    return m.group(1) if m else ""

def wrap_para(para_lines):
    """Join and re-wrap a list of prose lines."""
    if not para_lines:
        return []

    # Detect list item from the first line
    li = list_indent(para_lines[0])
    if li:
        ii, si = li
    else:
        ii = leading_indent(para_lines[0])
        si = ii

    text = " ".join(l.strip() for l in para_lines)
    wrapped = textwrap.fill(
        text,
        width=width,
        initial_indent=ii,
        subsequent_indent=si,
        break_long_words=False,
        break_on_hyphens=False,
    )
    return wrapped.split("\n")

# ── main pass ─────────────────────────────────────────────────────────────────

output = []
in_code_block = False
para_buf = []       # accumulates lines of the current prose paragraph

def flush_para():
    if para_buf:
        output.extend(wrap_para(para_buf))
        para_buf.clear()

for raw_line in lines:
    raw = raw_line.rstrip("\n")

    # Code-fence toggle
    if re.match(r"^```", raw):
        flush_para()
        in_code_block = not in_code_block
        output.append(raw)
        continue

    if in_code_block:
        output.append(raw)
        continue

    # Blank line → flush current paragraph, emit blank
    if raw.strip() == "":
        flush_para()
        output.append(raw)
        continue

    # Verbatim lines
    if is_verbatim(raw):
        flush_para()
        output.append(raw)
        continue

    # List items start a new paragraph
    if list_indent(raw):
        flush_para()
        para_buf.append(raw)
        continue

    # Indented block (blockquote / definition list continuation): treat as verbatim
    if raw.startswith("    ") or raw.startswith("\t"):
        flush_para()
        output.append(raw)
        continue

    # Regular prose — accumulate
    para_buf.append(raw)

flush_para()

with open(file_path, "w") as f:
    f.write("\n".join(output) + "\n")

print(f"Wrapped '{file_path}' at {width} characters.")
PYEOF
