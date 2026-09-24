#!/bin/bash
# Stop hook: at end of each agent turn, ask an LLM to identify any project-wide
# rule, decision, or constraint from the recent exchange that should be promoted
# to CLAUDE.md, then append it.
#
# Looks at BOTH the latest user message and the latest assistant text — so it
# captures (a) explicit user directives, and (b) cross-cutting decisions the
# assistant established this turn that future sessions should respect.

set -u

LOG="$(dirname "$0")/hook.log"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"; }

# Recursion guard: this hook spawns `claude -p`, which would re-trigger Stop.
[ "${CLAUDE_MD_HOOK_RUNNING:-0}" = "1" ] && exit 0

command -v jq >/dev/null 2>&1 || { log "skip: jq missing"; exit 0; }
command -v claude >/dev/null 2>&1 || { log "skip: claude missing"; exit 0; }

INPUT=$(cat)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "skip: no transcript ($TRANSCRIPT_PATH)"
  exit 0
fi
[ -z "$CWD" ] && CWD=$(pwd)
CLAUDE_MD="$CWD/CLAUDE.md"

# Last user message that actually has typed text (skip tool_result envelopes).
# Emit each non-empty text as a JSON-encoded line, take the last, then decode.
USER_TEXT=$(jq -c '
  select(.type == "user")
  | (if (.message.content | type) == "string" then .message.content
     else ([.message.content[]? | select(.type == "text") | .text] | join("\n"))
     end) as $txt
  | select($txt != "")
  | $txt
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1 | jq -r '.' 2>/dev/null)

# Last assistant message that has text content (skip tool_use-only turns).
ASSIST_TEXT=$(jq -c '
  select(.type == "assistant")
  | ([.message.content[]? | select(.type == "text") | .text] | join("\n")) as $txt
  | select($txt != "")
  | $txt
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1 | jq -r '.' 2>/dev/null)

# Skip slash-command/system artifacts and empty turns
case "$USER_TEXT" in
  ''|'<local-command-stdout>'*|'<command-name>'*|'<local-command-caveat>'*|'<command-message>'*)
    log "skip: synthetic user msg"
    exit 0
    ;;
esac

if [ -z "$USER_TEXT" ] && [ -z "$ASSIST_TEXT" ]; then
  log "skip: no content"
  exit 0
fi

EXISTING=""
[ -f "$CLAUDE_MD" ] && EXISTING=$(cat "$CLAUDE_MD")

PROMPT=$(cat <<EOF
You analyze the most recent turn of a Claude Code session and decide whether any
project-wide rule, decision, or constraint should be added to CLAUDE.md.

Look for:
1. Explicit user instructions intended for FUTURE work (rules, conventions, prohibitions, preferences).
2. Architectural/stack/design decisions established THIS turn that future sessions should respect.
3. Implicit constraints discovered (e.g. "this build needs flag X", "library Y is incompatible with Z", "spec says only color N for accent").

Skip:
- One-off task instructions ("fix this bug now", "rename this var").
- Anything already covered in the existing CLAUDE.md below — deduplicate strictly.
- Per-feature implementation details that do not generalize.
- Ephemeral state (current task, in-flight branch, plan for today).

Output rules:
- If new rules exist: ONLY markdown bullet lines starting with "- ". One rule per bullet.
- If no new permanent rule: output exactly the word NONE
- Match the language used by the user (Korean stays Korean).
- No preamble, no explanation, no code fences.

=== Existing CLAUDE.md ===
$EXISTING

=== Recent user message ===
$USER_TEXT

=== Recent assistant message ===
$ASSIST_TEXT
EOF
)

log "invoking claude -p (cwd=$CWD)"
# Run claude -p from a neutral directory so it does NOT pick up this project's
# CLAUDE.md as system context — otherwise the model treats the embedded
# CLAUDE.md as instructions and produces conversational replies.
ANALYSIS=$(cd "${TMPDIR:-/tmp}" && CLAUDE_MD_HOOK_RUNNING=1 claude -p --model haiku "$PROMPT" 2>>"$LOG")
ANALYSIS=$(printf '%s' "$ANALYSIS" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# Format guard: must be exactly "NONE" or every non-empty line must start with "- ".
# Anything else is treated as a model deviation and discarded.
if [ -z "$ANALYSIS" ] || [ "$ANALYSIS" = "NONE" ]; then
  log "no new rules"
  exit 0
fi
if printf '%s\n' "$ANALYSIS" | grep -vE '^(- |$)' | grep -q .; then
  log "discarded malformed output: $ANALYSIS"
  exit 0
fi

# First write: seed file with a header
if [ ! -f "$CLAUDE_MD" ]; then
  printf '# Project Rules\n\nAuto-captured from session feedback. Edit freely.\n\n' > "$CLAUDE_MD"
fi

printf '%s\n' "$ANALYSIS" >> "$CLAUDE_MD"
log "appended: $ANALYSIS"

printf '{"systemMessage": "CLAUDE.md updated with new directive(s)"}\n'
