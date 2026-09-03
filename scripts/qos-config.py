#!/usr/bin/env python3
"""QoS Harness configuration manager.

Uses only Python's standard library. Configuration is merged in this order:
1. ~/.config/qos-harness/config.json
2. <project>/.qos-harness.json
3. Existing environment variables (highest priority; export-shell never overwrites them)
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
import subprocess
from copy import deepcopy
from pathlib import Path
from typing import Any

DEFAULT_CONFIG: dict[str, Any] = {
    "version": 1,
    "project": {"name": ""},
    "engine": {
        "default": "codex",
        "verify_model": "",
        "verify_models": {"codex": "gpt-5.4-mini", "claude": "haiku", "agy": "gemini-2.5-flash"},
    },
    "verification": {"mode": "always", "max_cycles": 3},
    "tests": {"command": ""},
    "notifications": {
        "enabled": False,
        "provider": "n8n",
        "fallback_provider": "",
        "webhook": "",
        "token": "",
        "whatsapp_number": "",
        "n8n": {"webhook": "", "token": "", "number": ""},
        "evolution": {
            "base_url": "",
            "instance": "",
            "api_key": "",
            "number": "",
            "payload_format": "text"
        },
        "events": [
            "run_started",
            "phase_started",
            "phase_correction_started",
            "usage_limit_reached",
            "usage_limit_resumed",
            "phase_completed",
            "phase_already_complete",
            "phase_failed",
            "run_completed",
            "run_failed",
            "run_aborted",
        ],
    },
}

ENV_MAP: dict[str, tuple[str, ...]] = {
    "RALPH_PROJECT_NAME": ("project", "name"),
    "RALPH_ENGINE_DEFAULT": ("engine", "default"),
    "RALPH_CODEX_VERIFY_MODEL": ("engine", "verify_models", "codex"),
    "RALPH_CLAUDE_VERIFY_MODEL": ("engine", "verify_models", "claude"),
    "RALPH_AGY_VERIFY_MODEL": ("engine", "verify_models", "agy"),
    "RALPH_VERIFY": ("verification", "mode"),
    "RALPH_MAX_CYCLES": ("verification", "max_cycles"),
    "RALPH_TEST_CMD": ("tests", "command"),
    "RALPH_NOTIFY_ENABLED": ("notifications", "enabled"),
    "RALPH_NOTIFY_PROVIDER": ("notifications", "provider"),
    "RALPH_NOTIFY_FALLBACK_PROVIDER": ("notifications", "fallback_provider"),
    "RALPH_NOTIFY_WEBHOOK": ("notifications", "n8n", "webhook"),
    "RALPH_NOTIFY_TOKEN": ("notifications", "n8n", "token"),
    "RALPH_WHATSAPP_NUMBER": ("notifications", "whatsapp_number"),
    "RALPH_EVOLUTION_BASE_URL": ("notifications", "evolution", "base_url"),
    "RALPH_EVOLUTION_INSTANCE": ("notifications", "evolution", "instance"),
    "RALPH_EVOLUTION_API_KEY": ("notifications", "evolution", "api_key"),
    "RALPH_EVOLUTION_NUMBER": ("notifications", "evolution", "number"),
    "RALPH_EVOLUTION_PAYLOAD_FORMAT": ("notifications", "evolution", "payload_format"),
    "RALPH_NOTIFY_EVENTS": ("notifications", "events"),
}

SECRET_KEYS = {"token", "webhook", "whatsapp_number", "api_key", "number"}


def deep_merge(base: dict[str, Any], incoming: dict[str, Any]) -> dict[str, Any]:
    merged = deepcopy(base)
    for key, value in incoming.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"Configuration root must be an object: {path}")
    return data


def project_file(project: Path) -> Path:
    return project / ".qos-harness.json"


def global_file() -> Path:
    return Path.home() / ".config" / "qos-harness" / "config.json"


def load_config(project: Path) -> dict[str, Any]:
    config = deepcopy(DEFAULT_CONFIG)
    config = deep_merge(config, read_json(global_file()))
    config = deep_merge(config, read_json(project_file(project)))

    # Backward compatibility: engine.verify_model was the single verifier
    # model used before per-engine verifier models were introduced. Apply it
    # only to slots that were not explicitly configured.
    engine = config.setdefault("engine", {})
    verify_models = engine.setdefault("verify_models", {"codex": "gpt-5.4-mini", "claude": "haiku", "agy": "gemini-2.5-flash"})
    legacy_verify_model = engine.get("verify_model", "")
    if legacy_verify_model:
        raw_global = read_json(global_file())
        raw_project = read_json(project_file(project))
        explicit_models = deep_merge(
            nested_get(raw_global, ("engine", "verify_models")) or {},
            nested_get(raw_project, ("engine", "verify_models")) or {},
        )
        for engine_name in ("codex", "claude", "agy"):
            if engine_name not in explicit_models:
                verify_models[engine_name] = legacy_verify_model

    # Backward compatibility with v1.1 flat notification fields.
    notifications = config.get("notifications", {})
    n8n = notifications.setdefault("n8n", {})
    if notifications.get("webhook") and not n8n.get("webhook"):
        n8n["webhook"] = notifications["webhook"]
    if notifications.get("token") and not n8n.get("token"):
        n8n["token"] = notifications["token"]
    if notifications.get("whatsapp_number") and not n8n.get("number"):
        n8n["number"] = notifications["whatsapp_number"]
    evolution = notifications.setdefault("evolution", {})
    provider = notifications.get("provider", "n8n")
    active_number = nested_get(notifications, (provider, "number")) if provider in {"n8n", "evolution"} else ""
    if active_number:
        notifications["whatsapp_number"] = active_number
    elif evolution.get("number") and not notifications.get("whatsapp_number"):
        notifications["whatsapp_number"] = evolution["number"]
    return config


def nested_get(data: dict[str, Any], path: tuple[str, ...]) -> Any:
    current: Any = data
    for part in path:
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def normalize_env_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return ",".join(str(item) for item in value)
    return str(value)


def validate(config: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if config.get("version") != 1:
        errors.append("version must be 1")
    if nested_get(config, ("engine", "default")) not in {"codex", "claude", "agy"}:
        errors.append("engine.default must be 'codex' or 'claude'")
    verify_models = nested_get(config, ("engine", "verify_models"))
    if not isinstance(verify_models, dict):
        errors.append("engine.verify_models must be an object")
    else:
        for engine_name in ("codex", "claude", "agy"):
            value = verify_models.get(engine_name, "")
            if not isinstance(value, str):
                errors.append(f"engine.verify_models.{engine_name} must be a string")
    if nested_get(config, ("verification", "mode")) not in {"always", "auto", "off"}:
        errors.append("verification.mode must be always, auto, or off")
    max_cycles = nested_get(config, ("verification", "max_cycles"))
    if not isinstance(max_cycles, int) or max_cycles < 1:
        errors.append("verification.max_cycles must be an integer >= 1")
    provider = nested_get(config, ("notifications", "provider"))
    if provider not in {"n8n", "evolution", "none"}:
        errors.append("notifications.provider must be n8n, evolution, or none")
    fallback = nested_get(config, ("notifications", "fallback_provider"))
    if fallback not in {"", "n8n", "evolution", "none"}:
        errors.append("notifications.fallback_provider must be blank, n8n, evolution, or none")
    if fallback and fallback == provider:
        errors.append("notifications.fallback_provider must differ from provider")
    enabled = nested_get(config, ("notifications", "enabled"))
    if not isinstance(enabled, bool):
        errors.append("notifications.enabled must be true or false")
    if enabled and provider == "n8n":
        if not nested_get(config, ("notifications", "n8n", "webhook")):
            errors.append("notifications.n8n.webhook is required for n8n")
    if enabled and provider == "evolution":
        required = ("base_url", "instance", "api_key", "number")
        for field in required:
            if not nested_get(config, ("notifications", "evolution", field)):
                errors.append(f"notifications.evolution.{field} is required for evolution")
        payload_format = nested_get(config, ("notifications", "evolution", "payload_format"))
        if payload_format not in {"text", "text_message"}:
            errors.append("notifications.evolution.payload_format must be text or text_message")
    events = nested_get(config, ("notifications", "events"))
    if not isinstance(events, list) or not all(isinstance(v, str) for v in events):
        errors.append("notifications.events must be an array of strings")
    return errors


def redacted(data: Any, key: str = "") -> Any:
    if isinstance(data, dict):
        return {k: redacted(v, k) for k, v in data.items()}
    if isinstance(data, list):
        return [redacted(v) for v in data]
    if key in SECRET_KEYS and data:
        text = str(data)
        if len(text) <= 8:
            return "***"
        return f"{text[:4]}…{text[-4:]}"
    return data


def prompt(label: str, default: str = "", secret: bool = False) -> str:
    suffix = f" [{default}]" if default else ""
    if secret:
        import getpass
        value = getpass.getpass(f"{label}{suffix}: ")
    else:
        value = input(f"{label}{suffix}: ").strip()
    return value or default


def prompt_bool(label: str, default: bool) -> bool:
    marker = "Y/n" if default else "y/N"
    answer = input(f"{label} [{marker}]: ").strip().lower()
    if not answer:
        return default
    return answer in {"y", "yes", "s", "sim"}


def configure(project: Path, scope: str) -> Path:
    target = global_file() if scope == "global" else project_file(project)
    existing = load_config(project)
    cfg = deepcopy(existing)
    cfg["project"]["name"] = prompt("Project name", cfg["project"].get("name") or project.name)
    cfg["engine"]["default"] = prompt("Default engine (codex/claude/agy)", cfg["engine"].get("default", "codex"))
    verify_models = cfg["engine"].setdefault("verify_models", {"codex": "gpt-5.4-mini", "claude": "haiku", "agy": "gemini-2.5-flash"})
    verify_models["codex"] = prompt(
        "Codex verification model (blank = Codex default)",
        verify_models.get("codex", ""),
    )
    verify_models["claude"] = prompt(
        "Default verifier model for Claude (usually a cheaper one)",
        verify_models.get("claude", "haiku"),
    )
    verify_models["agy"] = prompt(
        "Default verifier model for Antigravity (usually a cheaper one)",
        verify_models.get("agy", "gemini-2.5-flash"),
    )
    # Stop writing the legacy field in newly generated configurations.
    cfg["engine"].pop("verify_model", None)
    cfg["verification"]["mode"] = prompt("Verification mode (always/auto/off)", cfg["verification"].get("mode", "always"))
    max_cycles = prompt("Maximum correction cycles", str(cfg["verification"].get("max_cycles", 3)))
    cfg["verification"]["max_cycles"] = int(max_cycles)
    cfg["tests"]["command"] = prompt("Test command override (blank = auto-detect)", cfg["tests"].get("command", ""))

    enabled = prompt_bool("Enable notifications", bool(cfg["notifications"].get("enabled", False)))
    cfg["notifications"]["enabled"] = enabled
    if enabled:
        provider = prompt("Notification provider (n8n/evolution)", cfg["notifications"].get("provider", "n8n"))
        cfg["notifications"]["provider"] = provider
        fallback = prompt("Fallback provider (blank/n8n/evolution)", cfg["notifications"].get("fallback_provider", ""))
        cfg["notifications"]["fallback_provider"] = fallback
        if provider == "n8n" or fallback == "n8n":
            n8n = cfg["notifications"].setdefault("n8n", {})
            n8n["webhook"] = prompt("n8n webhook URL", n8n.get("webhook", ""))
            n8n["token"] = prompt("Webhook bearer token", n8n.get("token", ""), secret=True)
            n8n["number"] = prompt("WhatsApp number for n8n", n8n.get("number", cfg["notifications"].get("whatsapp_number", "")))
        if provider == "evolution" or fallback == "evolution":
            evo = cfg["notifications"].setdefault("evolution", {})
            evo["base_url"] = prompt("Evolution API base URL", evo.get("base_url", ""))
            evo["instance"] = prompt("Evolution instance name", evo.get("instance", ""))
            evo["api_key"] = prompt("Evolution API key", evo.get("api_key", ""), secret=True)
            evo["number"] = prompt("WhatsApp destination number", evo.get("number", cfg["notifications"].get("whatsapp_number", "")))
            evo["payload_format"] = prompt("Evolution payload format (text/text_message)", evo.get("payload_format", "text"))
        active_number = nested_get(cfg, ("notifications", provider, "number")) or cfg["notifications"].get("whatsapp_number", "")
        cfg["notifications"]["whatsapp_number"] = active_number

    errors = validate(cfg)
    if errors:
        raise ValueError("; ".join(errors))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        target.chmod(0o600)
    except OSError:
        pass
    return target


def export_shell(config: dict[str, Any]) -> None:
    for env_name, path in ENV_MAP.items():
        if env_name in os.environ:
            continue
        value = nested_get(config, path)
        if value in (None, "", []):
            continue
        print(f"export {env_name}={shlex.quote(normalize_env_value(value))}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage QoS Harness configuration")
    parser.add_argument("--project", default=".", help="Project directory")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("show", help="Show merged configuration with secrets redacted")
    sub.add_parser("validate", help="Validate merged configuration")
    sub.add_parser("export-shell", help="Print shell exports for Ralph")
    test_parser = sub.add_parser("test-notification", help="Send a test notification using the configured provider")
    test_parser.add_argument("--message", default="🧪 QoS Harness notification test succeeded.")
    init_parser = sub.add_parser("init", help="Interactively create configuration")
    init_parser.add_argument("--scope", choices=["project", "global"], default="project")
    args = parser.parse_args()

    project = Path(args.project).expanduser().resolve()
    try:
        if args.command == "init":
            path = configure(project, args.scope)
            print(f"Configuration written to {path}")
            return 0
        config = load_config(project)
        errors = validate(config)
        if args.command == "validate":
            if errors:
                for error in errors:
                    print(f"ERROR: {error}", file=sys.stderr)
                return 1
            print("QoS Harness configuration: OK")
            return 0
        if errors:
            raise ValueError("; ".join(errors))
        if args.command == "test-notification":
            env = os.environ.copy()
            for env_name, path in ENV_MAP.items():
                if env_name not in env:
                    value = nested_get(config, path)
                    if value not in (None, "", []):
                        env[env_name] = normalize_env_value(value)
            dispatcher = Path(__file__).with_name("notify-dispatcher.sh")
            if not dispatcher.exists():
                raise ValueError(f"Notification dispatcher not found: {dispatcher}")
            env["QOS_NOTIFY_STRICT"] = "true"
            result = subprocess.run([str(dispatcher), "manual_test", args.message], env=env, check=False)
            if result.returncode != 0:
                raise ValueError("Notification test failed")
            print(f"Notification test sent using {nested_get(config, ('notifications', 'provider'))}")
            return 0
        if args.command == "show":
            print(json.dumps(redacted(config), ensure_ascii=False, indent=2))
            return 0
        if args.command == "export-shell":
            export_shell(config)
            return 0
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
