#!/usr/bin/env bash

# common.sh — Engine Adapter Contract for QoS Harness
#
# Each engine adapter (e.g., codex.sh, claude.sh) must implement these functions.

# Validates if the CLI is installed and configured.
# Should exit 1 with a clear error message if not.
engine_check_availability() {
  echo "engine_check_availability not implemented" >&2
  exit 1
}

# Returns the default verification model.
engine_get_default_verify_model() {
  echo "engine_get_default_verify_model not implemented" >&2
  exit 1
}

# Executes the engine for task implementation.
# $1: prompt_file
# $2: log_file
engine_run_impl() {
  echo "engine_run_impl not implemented" >&2
  exit 1
}

# Executes the engine for independent verification.
# $1: prompt_file
# $2: log_file
# $3: model (optional)
engine_run_verify() {
  echo "engine_run_verify not implemented" >&2
  exit 1
}

# Detects rate limits from the tail of the log.
# $1: tail_txt (last N lines of the log)
# Returns 0 and echoes the reset epoch (or 0) if a limit is detected.
# Returns 1 if no limit is detected.
engine_detect_usage_limit() {
  echo "engine_detect_usage_limit not implemented" >&2
  exit 1
}

# Checks if the engine executed successfully (Gate 0).
# $1: log_file
# $2: rc (exit code of the engine command)
# Sets the global GATE_CAUSE variable if it fails.
# Returns 0 on success, 1 on failure.
engine_check_success() {
  echo "engine_check_success not implemented" >&2
  exit 1
}
