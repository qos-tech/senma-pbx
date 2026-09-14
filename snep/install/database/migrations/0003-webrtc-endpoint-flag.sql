-- TASK-0035B: WebRTC endpoint contract flag on peers.
--
-- When peers.webrtc=1, Snep_PjsipConf emits webrtc=yes (and forces
-- direct_media=no). Asterisk's webrtc=yes implies the DTLS/ICE/AVPF/
-- RTCP-mux defaults needed for browser WebRTC media. Public WSS TLS
-- remains on the reverse proxy (TASK-0035A); endpoint DTLS is a
-- separate lifecycle (dtls_auto_generate_cert via webrtc=yes).
-- Idempotent for fresh apply via schema_migrations tracker only.

ALTER TABLE peers
  ADD COLUMN webrtc TINYINT(1) NOT NULL DEFAULT 0 AFTER transport_id;
