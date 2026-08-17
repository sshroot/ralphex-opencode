#!/usr/bin/env bash
# Translate OpenCode JSONL output to the Claude stream-json format expected by Ralphex.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: jq is required but not found" >&2; exit 1; }
command -v opencode >/dev/null 2>&1 || { echo "error: opencode is required but not found" >&2; exit 1; }

OPENCODE_MODEL="${OPENCODE_MODEL:-}"
OPENCODE_VARIANT="${OPENCODE_VARIANT:-${OPENCODE_EFFORT:-${OPENCODE_REASONING:-}}}"
OPENCODE_VERBOSE="${OPENCODE_VERBOSE:-0}"

require_value() {
    local flag="$1" value="${2:-}"
    if [[ -z "$value" || "$value" == -* ]]; then
        echo "error: $flag requires a non-empty value" >&2
        exit 1
    fi
    printf '%s\n' "$value"
}

prompt=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p) prompt="${2:-}"; shift 2 ;;
        --model) OPENCODE_MODEL=$(require_value "$1" "${2:-}"); shift 2 ;;
        --model=*) OPENCODE_MODEL=$(require_value "--model" "${1#--model=}"); shift ;;
        --effort) OPENCODE_VARIANT=$(require_value "$1" "${2:-}"); shift 2 ;;
        --effort=*) OPENCODE_VARIANT=$(require_value "--effort" "${1#--effort=}"); shift ;;
        --variant) OPENCODE_VARIANT=$(require_value "$1" "${2:-}"); shift 2 ;;
        --variant=*) OPENCODE_VARIANT=$(require_value "--variant" "${1#--variant=}"); shift ;;
        *) shift ;;
    esac
done

if [[ -z "$prompt" && ! -t 0 ]]; then
    prompt=$(cat)
fi
[[ -n "$prompt" ]] || { echo "error: no prompt provided (expected -p flag or stdin)" >&2; exit 1; }

if [[ -z "${OPENCODE_CONFIG_CONTENT:-}" ]]; then
    OPENCODE_CONFIG_CONTENT='{"permission":{"*":"allow"}}'
else
    printf '%s\n' "$OPENCODE_CONFIG_CONTENT" | jq empty >/dev/null 2>&1 || {
        echo "error: OPENCODE_CONFIG_CONTENT is not valid JSON" >&2; exit 1;
    }
    OPENCODE_CONFIG_CONTENT=$(printf '%s\n' "$OPENCODE_CONFIG_CONTENT" | jq -c '. * {"permission":{"*":"allow"}}')
fi
export OPENCODE_CONFIG_CONTENT

if [[ "$OPENCODE_VERBOSE" != "0" && "$OPENCODE_VERBOSE" != "1" ]]; then
    echo "warning: OPENCODE_VERBOSE must be 0 or 1; using 0" >&2
    OPENCODE_VERBOSE=0
fi

if [[ "$prompt" == *"<<<RALPHEX:REVIEW_DONE>>>"* ]]; then
    prompt=$'Ralphex review adapter for OpenCode:\n- Execute review tasks sequentially.\n- Apply fixes after completing the review steps.\n- Preserve all <<<RALPHEX:...>>> signals unchanged.'$'\n\n'"$prompt"
fi

args=(run --format json)
[[ -n "$OPENCODE_MODEL" ]] && args+=(--model "$OPENCODE_MODEL")
[[ -n "$OPENCODE_VARIANT" ]] && args+=(--variant "$OPENCODE_VARIANT")
args+=("$prompt")

tmp_dir=$(mktemp -d)
stderr_file="$tmp_dir/stderr"
stdout_pipe="$tmp_dir/stdout.fifo"
instructions_file="$tmp_dir/output-rules.md"
mkfifo "$stdout_pipe"
cat > "$instructions_file" <<'EOF'
# Output rules
- Be concise and direct.
- Do not restate the user's prompt.
- Never quote <<<RALPHEX:...>>> signal strings unless emitting the actual signal requested by Ralphex.
EOF
OPENCODE_CONFIG_CONTENT=$(printf '%s\n' "$OPENCODE_CONFIG_CONTENT" | jq -c --arg f "$instructions_file" '.instructions = ((.instructions // []) + [$f])')
export OPENCODE_CONFIG_CONTENT

cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

opencode_pid=""
forward_signal() {
    [[ -n "$opencode_pid" ]] && kill -TERM "$opencode_pid" 2>/dev/null || true
}
trap forward_signal TERM

opencode "${args[@]}" >"$stdout_pipe" 2>"$stderr_file" &
opencode_pid=$!

while IFS= read -r line || [[ -n "$line" ]]; do
    translated=$(printf '%s\n' "$line" | jq -c --argjson verbose "$OPENCODE_VERBOSE" '
        if .type == "text" then
            {type: "content_block_delta", delta: {type: "text_delta", text: .part.text}}
        elif .type == "step_finish" then
            {type: "result", result: ""}
        elif .type == "step_start" and $verbose == 1 then
            {type: "content_block_delta", delta: {type: "text_delta", text: "[step started]\n"}}
        else empty
        end
    ' 2>/dev/null) || true
    if [[ -n "$translated" ]]; then
        printf '%s\n' "$translated"
    elif ! printf '%s\n' "$line" | jq -e . >/dev/null 2>&1; then
        printf '%s\n' "$line"
    fi
done < "$stdout_pipe"

opencode_exit=0
wait "$opencode_pid" || opencode_exit=$?
opencode_pid=""

if [[ -s "$stderr_file" ]]; then
    while IFS= read -r err_line || [[ -n "$err_line" ]]; do
        [[ -z "$err_line" ]] && continue
        printf '%s\n' "$err_line" | jq -Rc '{type: "content_block_delta", delta: {type: "text_delta", text: .}}'
    done < "$stderr_file"
fi

echo '{"type":"result","result":""}'
exit "$opencode_exit"
