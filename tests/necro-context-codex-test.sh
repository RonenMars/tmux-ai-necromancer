#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME/.codex/sessions/2026/06/18"

UUID="019edbdb-61c5-7162-8b28-9eac82bbfa58"
CWD="$TMP/workspace"
mkdir -p "$CWD"

cat > "$HOME/.codex/sessions/2026/06/18/rollout-2026-06-18T20-50-48-$UUID.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$UUID","cwd":"$CWD"}}
{"type":"response_item","role":"user","payload":{"role":"user","content":[{"type":"input_text","text":"Review the Codex support"}]}}
{"type":"response_item","role":"assistant","payload":{"role":"assistant","content":[{"type":"output_text","text":"Codex support needs parser coverage"}]}}
EOF

SNAP="$TMP/snapshot.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":0,"window_name":"w","cwd":"$CWD","prev_cmd":"codex","agent":"codex","uuid":"$UUID","uuid_source":"latest-jsonl","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

"$ROOT/scripts/necro-context.sh" "$SNAP" >/dev/null

OUT="${SNAP%.jsonl}.enriched.jsonl"
first_user="$(jq -r '.first_user' "$OUT")"
last_assistant="$(jq -r '.last_assistant' "$OUT")"

[ "$first_user" = "Review the Codex support" ] || {
  echo "first_user mismatch: $first_user" >&2
  exit 1
}

[ "$last_assistant" = "Codex support needs parser coverage" ] || {
  echo "last_assistant mismatch: $last_assistant" >&2
  exit 1
}
