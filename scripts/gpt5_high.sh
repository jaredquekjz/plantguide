#!/usr/bin/env bash
set -euo pipefail

# gpt5_high.sh — tiny wrapper to call the Responses API
# with reasoning effort set to "high" for reasoning-capable models (e.g., gpt-5).
#
# Usage examples:
#   scripts/gpt5_high.sh --input "Summarize this paragraph: ..."
#   echo "Analyze this data" | scripts/gpt5_high.sh --model gpt-5 --temperature 0.3
#   scripts/gpt5_high.sh --input "..." --max_output_tokens 800 --debug
#
# Requirements:
#   - curl and jq available in PATH
#   - OPENAI_API_KEY set in the environment

err() { echo "${1}" >&2; }

command -v curl >/dev/null 2>&1 || { err "Missing dependency: curl"; exit 2; }
command -v jq   >/dev/null 2>&1 || { err "Missing dependency: jq"; exit 2; }

: "${OPENAI_API_KEY?Missing OPENAI_API_KEY in environment}"

MODEL="gpt-5"
EFFORT="high"
INPUT=""
SYSTEM=""
TEMP="0.3"
MAX_OUT="1024"
RAW_JSON="false"
DEBUG="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL=${2:?}; shift ;;
    --model=*) MODEL=${1#*=} ;;
    --effort) EFFORT=${2:?}; shift ;;
    --effort=*) EFFORT=${1#*=} ;;
    --input) INPUT=${2:?}; shift ;;
    --input=*) INPUT=${1#*=} ;;
    --system) SYSTEM=${2:?}; shift ;;
    --system=*) SYSTEM=${1#*=} ;;
    --temperature) TEMP=${2:?}; shift ;;
    --temperature=*) TEMP=${1#*=} ;;
    --max_output_tokens) MAX_OUT=${2:?}; shift ;;
    --max_output_tokens=*) MAX_OUT=${1#*=} ;;
    --raw|--json) RAW_JSON="true" ;;
    --debug|--verbose) DEBUG="true" ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--model gpt-5] [--effort high] [--input TEXT]|[stdin] \
          [--system SYS] [--temperature 0.3] [--max_output_tokens 1024] \
          [--raw] [--debug]

Sends a Responses API request with reasoning.effort applied.
If --input is not given, reads from stdin if available.
EOF
      exit 0 ;;
    *) err "Unknown flag: $1"; exit 2 ;;
  esac
  shift
enddone

# Read from stdin if no --input provided and stdin is not a TTY
if [[ -z "$INPUT" ]] && [ ! -t 0 ]; then
  INPUT=$(cat)
fi

if [[ -z "$INPUT" ]]; then
  err "No input provided. Use --input TEXT or pipe stdin."; exit 2
fi

# Validate numeric fields deterministically
if ! [[ "$TEMP" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then err "--temperature must be numeric"; exit 2; fi
if ! [[ "$MAX_OUT" =~ ^[0-9]+$ ]]; then err "--max_output_tokens must be integer"; exit 2; fi

# Build JSON safely using jq
PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --arg effort "$EFFORT" \
  --arg input "$INPUT" \
  --arg system "$SYSTEM" \
  --argjson temperature "$TEMP" \
  --argjson max_output_tokens "$MAX_OUT" \
  '{
      model: $model,
      reasoning: { effort: $effort },
      input: $input,
      temperature: $temperature,
      max_output_tokens: $max_output_tokens
    } | if ($system|length) > 0 then . + { system: $system } else . end')

if [[ "$DEBUG" == "true" ]]; then
  err "Effective parameters: model=$MODEL, effort=$EFFORT, temperature=$TEMP, max_output_tokens=$MAX_OUT, system_len=${#SYSTEM}, input_chars=${#INPUT}"
  err "Request JSON:"; echo "$PAYLOAD" | jq . >&2
fi

RESP=$(curl -sS https://api.openai.com/v1/responses \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H 'Content-Type: application/json' \
  --data "$PAYLOAD")

# Fail fast on HTTP or API error messages
if echo "$RESP" | jq -e '.error' >/dev/null 2>&1; then
  err "API Error:"; echo "$RESP" | jq . >&2; exit 1
fi

if [[ "$RAW_JSON" == "true" ]]; then
  echo "$RESP" | jq .
  exit 0
fi

# Try to print the aggregated output_text; fall back to common fields
OUT=$(echo "$RESP" | jq -r '(.output_text // .output[0].content[0].text // .choices[0].message.content // .content // empty)')
if [[ -n "$OUT" ]]; then
  printf "%s\n" "$OUT"
else
  # If structure unknown, print the whole response
  echo "$RESP" | jq .
fi

