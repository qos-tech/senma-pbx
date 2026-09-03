#!/usr/bin/env bash

engine_check_availability() {
  if ! command -v claude &> /dev/null; then
    fail "Claude Code CLI nao encontrado. Instale com: npm install -g @anthropic-ai/claude-code"
    exit 1
  fi
}

engine_get_default_verify_model() {
  echo "${RALPH_CLAUDE_VERIFY_MODEL:-haiku}"
}

engine_run_impl() {
  local prompt_file="$1" log_file="$2"
  # JSON: o exit code do CLI e sinal fraco; o gate 0 le is_error.
  # < /dev/null: claude -p le stdin quando nao e TTY. Sem o redirect ele
  # consome o stream de quem chamou (ex: o manifest do loop de fases).
  env -u CLAUDECODE claude --dangerously-skip-permissions \
    -p "$(cat "$prompt_file")" \
    --output-format json < /dev/null 2>&1 | tee "$log_file"
}

engine_run_verify() {
  local prompt_file="$1" log_file="$2" model="$3"
  if [ -n "$model" ]; then
    env -u CLAUDECODE claude --dangerously-skip-permissions \
      --model "$model" \
      -p "$(cat "$prompt_file")" \
      --allowedTools "Read,Glob,Grep" \
      --output-format text < /dev/null 2>&1 | tee "$log_file"
  else
    env -u CLAUDECODE claude --dangerously-skip-permissions \
      -p "$(cat "$prompt_file")" \
      --allowedTools "Read,Glob,Grep" \
      --output-format text < /dev/null 2>&1 | tee "$log_file"
  fi
}

engine_detect_usage_limit() {
  local tail_txt="$1"
  if ! grep -qiE 'usage limit reached' <<< "$tail_txt"; then
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
  if ! grep -qF '"type":"result"' "$log_file" && ! grep -qF '"type": "result"' "$log_file"; then
    GATE_CAUSE="O engine terminou sem emitir um resultado. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi
  if grep -qE '"is_error"[[:space:]]*:[[:space:]]*true' "$log_file"; then
    GATE_CAUSE="O engine reportou is_error=true. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    GATE_CAUSE="O engine saiu com codigo $rc. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi
  return 0
}
