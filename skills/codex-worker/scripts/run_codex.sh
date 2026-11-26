#!/opt/homebrew/bin/bash
set -euo pipefail

CWD="${PWD}"
SESSION_ID=""
PROMPT=""
PROMPT_FILE=""
MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)
      CWD="$2"
      shift 2
      ;;
    --session)
      SESSION_ID="$2"
      shift 2
      ;;
    --prompt)
      PROMPT="$2"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
用法:
  run_codex.sh [--cwd <dir>] [--session <uuid>] [--model <model>] (--prompt "<text>" | --prompt-file <file>)
USAGE
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "找不到 prompt 文件: $PROMPT_FILE" >&2
    exit 2
  fi
  PROMPT="$(cat "$PROMPT_FILE")"
fi

if [[ -z "$PROMPT" ]]; then
  echo "必须提供 --prompt 或 --prompt-file" >&2
  exit 2
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
LOG_FILE="/tmp/codex-worker-${RUN_ID}.jsonl"
SUMMARY_FILE="/tmp/codex-worker-${RUN_ID}.md"

cd "$CWD"

MODEL_ARGS=()
if [[ -n "$MODEL" ]]; then
  MODEL_ARGS=(-m "$MODEL")
fi

set +e
if [[ -n "$SESSION_ID" ]]; then
  codex exec resume "$SESSION_ID" "${MODEL_ARGS[@]}" --json -o "$SUMMARY_FILE" - <<< "$PROMPT" > "$LOG_FILE" 2>&1
  EXIT_CODE=$?
else
  codex exec --approve-for-me "${MODEL_ARGS[@]}" --json -o "$SUMMARY_FILE" - <<< "$PROMPT" > "$LOG_FILE" 2>&1
  EXIT_CODE=$?
fi
set -e

EXTRACTED_SESSION=$(/opt/homebrew/bin/python3 - "$LOG_FILE" "$SESSION_ID" <<'PY' 2>/dev/null || true
import json, re, sys

log_path = sys.argv[1]
fallback = sys.argv[2] if len(sys.argv) > 2 else ""
uuid_re = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I)

found = ""
try:
    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        for i, line in enumerate(f):
            if i > 30:
                break
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    for key in ("thread_id", "session_id", "conversation_id", "id"):
                        val = obj.get(key)
                        if isinstance(val, str) and uuid_re.fullmatch(val):
                            found = val
                            break
                    if found:
                        break
            except Exception:
                pass
            m = uuid_re.search(line)
            if m:
                found = m.group(0)
                break
except Exception:
    pass

print(found or fallback)
PY
)

echo "EXIT_CODE=${EXIT_CODE}"
echo "SESSION_ID=${EXTRACTED_SESSION}"
echo "SUMMARY_FILE=${SUMMARY_FILE}"
echo "LOG_FILE=${LOG_FILE}"

exit "$EXIT_CODE"
