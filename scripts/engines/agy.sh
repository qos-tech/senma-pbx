#!/usr/bin/env bash

engine_check_availability() {
  if ! command -v agy &> /dev/null; then
    fail "Google Antigravity CLI (agy) nao encontrado. Instale-o para usar a engine agy."
    exit 1
  fi
}

engine_get_default_verify_model() {
  echo "${RALPH_AGY_VERIFY_MODEL:-gemini-2.5-flash}"
}

engine_run_impl() {
  local prompt_file="$1" log_file="$2"
  local timeout="${RALPH_AGY_PRINT_TIMEOUT:-30m}"
  
  if [ -n "${RALPH_AGY_MODEL:-}" ]; then
    agy --mode accept-edits --add-dir "$(pwd)" --dangerously-skip-permissions --print-timeout "$timeout" --model "$RALPH_AGY_MODEL" --print "$(cat "$prompt_file")" 2>&1 | tee "$log_file"
  else
    agy --mode accept-edits --add-dir "$(pwd)" --dangerously-skip-permissions --print-timeout "$timeout" --print "$(cat "$prompt_file")" 2>&1 | tee "$log_file"
  fi
}

engine_run_verify() {
  local prompt_file="$1" log_file="$2" model="$3"
  local timeout="${RALPH_AGY_PRINT_TIMEOUT:-30m}"

  if [ -n "$model" ]; then
    agy --mode plan --add-dir "$(pwd)" --dangerously-skip-permissions --print-timeout "$timeout" --model "$model" --print "$(cat "$prompt_file")" 2>&1 | tee "$log_file"
  else
    agy --mode plan --add-dir "$(pwd)" --dangerously-skip-permissions --print-timeout "$timeout" --print "$(cat "$prompt_file")" 2>&1 | tee "$log_file"
  fi
}

engine_detect_usage_limit() {
  local tail_txt="$1"
  
  # "If no stable reset timestamp format is known, detect the limit conservatively without inventing an epoch."
  if ! grep -qiE 'rate limit reached|quota exceeded|usage limit|429 too many requests|exhausted' <<< "$tail_txt"; then
    return 1
  fi
  
  local epoch
  epoch=$(grep -oiE 'reset[a-z ]*[0-9]{10,13}' <<< "$tail_txt" | grep -oE '[0-9]{10,13}' | tail -1 || true)
  
  echo "${epoch:-0}"
  return 0
}

engine_check_success() {
  local log_file="$1" rc="$2"
  
  if [ "$rc" -ne 0 ]; then
    GATE_CAUSE="O engine agy saiu com codigo $rc (possivel timeout, falta de permissao ou falha interna). Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi
  
  return 0
}
