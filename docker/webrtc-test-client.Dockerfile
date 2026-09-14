# SENMA WebRTC media test client (TASK-0035B).
#
# Disposable image: SIP-over-WSS REGISTER + INVITE with a real WebRTC
# (aiortc) SDP offer/answer, proving DTLS-SRTP media against Asterisk.
# Runs on the Docker Compose network so ICE candidates stay reachable
# without publishing Asterisk RTP to the host.
#
# NOT part of the production runtime topology.

FROM python:3.12-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential pkg-config \
        libavformat-dev libavcodec-dev libavdevice-dev \
        libavutil-dev libswscale-dev libswresample-dev \
        libopus-dev libvpx-dev libsrtp2-dev \
    && pip install --no-cache-dir 'aiortc==1.15.0' 'numpy==2.2.6' \
    && apt-get purge -y build-essential pkg-config \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY webrtc-test-client/webrtc_sip_media.py /usr/local/bin/webrtc_sip_media.py
RUN chmod +x /usr/local/bin/webrtc_sip_media.py

ENTRYPOINT ["python3", "/usr/local/bin/webrtc_sip_media.py"]
