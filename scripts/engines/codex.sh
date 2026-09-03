#!/usr/bin/env bash

engine_check_availability() {
  if ! command -v codex &> /dev/null; then
    fail "codex CLI nao encontrado. Instale com: npm install -g @openai/codex"
    exit 1
  fi
}

engine_get_default_verify_model() {
  echo "${RALPH_CODEX_VERIFY_MODEL:-gpt-5.4-mini}"
}

engine_run_impl() {
  local prompt_file="$1" log_file="$2"
  codex exec --sandbox danger-full-access - < "$prompt_file" 2>&1 | tee "$log_file"
}

engine_run_verify() {
  local prompt_file="$1" log_file="$2" model="$3"
  # Bash 3.2 (macOS) + set -u falha ao expandir array vazia.
  # Use ramos explicitos para incluir --model somente quando definido.
  if [ -n "$model" ]; then
    codex exec --sandbox read-only --model "$model" - < "$prompt_file" 2>&1 | tee "$log_file"
  else
    codex exec --sandbox read-only - < "$prompt_file" 2>&1 | tee "$log_file"
  fi
}

engine_detect_usage_limit() {
  local tail_txt="$1"
  if ! grep -qiE 'rate limit reached|quota exceeded|usage limit reached' <<< "$tail_txt"; then
    return 1
  fi

  local epoch
  epoch=$(grep -oiE 'usage limit reached[^0-9]*[0-9]{10,13}' <<< "$tail_txt" \
    | grep -oE '[0-9]{10,13}' | tail -1 || true)
  
  if [ -z "$epoch" ]; then
    epoch=$(grep -oiE 'reset[a-z ]*[0-9]{10,13}' <<< "$tail_txt" \
      | grep -oE '[0-9]{10,13}' | tail -1 || true)
  fi

  echo "${epoch:-0}"
  return 0
}

engine_check_success() {
  local log_file="$1" rc="$2"
  if [ "$rc" -ne 0 ]; then
    GATE_CAUSE="O engine saiu com codigo $rc. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi
  return 0
}
