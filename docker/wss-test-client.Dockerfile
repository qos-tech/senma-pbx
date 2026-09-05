# wss-test-client image -- TASK-0028Z regression tooling only.
#
# NOT part of the SENMA runtime topology (no service in compose.yaml), same
# convention as docker/baresip-test.Dockerfile: scripts/wss-platform-smoke-
# test.sh builds this on demand and runs disposable containers from it on
# the same Docker network as the real `asterisk` service.
#
# baresip (docker/baresip-test.Dockerfile) cannot prove this task's
# contract -- its Debian package has no SIP-over-WebSocket transport
# compiled in at all (confirmed: no "ws"/"websocket" strings anywhere in
# the shipped binary). Proving a real TLS handshake -> WebSocket upgrade at
# `/ws` -> SIP REGISTER over that WebSocket -> PJSIP registration needs a
# client that actually speaks SIP-over-WebSocket (RFC 7118); Python's
# standard library (socket/ssl/hashlib, no third-party packages, no pip
# install, no network access needed at build or run time) is enough to
# implement that minimal client directly -- see
# docker/wss-test-client/wss_sip_register.py and
# docs/tasks/0028z-wss-asterisk-http-enablement.md.
FROM debian:13-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

COPY wss-test-client/wss_sip_register.py /usr/local/bin/wss_sip_register.py
RUN chmod +x /usr/local/bin/wss_sip_register.py

ENTRYPOINT ["python3", "/usr/local/bin/wss_sip_register.py"]
