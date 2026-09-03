---
description: Configure QoS Harness project/global settings and notifications without exposing secrets.
allowed-tools: Read, Glob, Grep, Bash
---

# config

Use `./scripts/qos-config.sh` to manage QoS Harness configuration.

- Run `./scripts/qos-config.sh show` to display the merged configuration with secrets redacted.
- Run `./scripts/qos-config.sh validate` to validate it.
- Run `./scripts/qos-config.sh init` for project configuration.
- Run `./scripts/qos-config.sh init --scope global` for user-wide defaults.

Configuration precedence is global file, project file, then environment variables. Never print raw tokens, webhook secrets or phone numbers. If the user asks to configure it, execute the interactive command in the terminal rather than manually creating secret-bearing files.
