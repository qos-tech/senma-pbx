# baresip test-endpoint image -- TASK-0009 call-smoke tooling only.
#
# NOT part of the SENMA runtime topology (no service in compose.yaml).
# scripts/call-smoke-test.sh builds this on demand and runs two disposable
# containers from it (extensions 1000/1001) to prove a real PJSIP call
# without requiring physical phones. baresip (not SIPp) because Debian 13
# has no SIPp package at all (verified: empty apt-cache result); baresip
# 1.1.0 and sipsak are both real Debian 13 packages. See
# docs/tasks/0009-first-pjsip-call.md.
FROM debian:13-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        baresip ca-certificates netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*
