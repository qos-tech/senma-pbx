-- TASK-0035A: realign seeded websocket signaling behind reverse-proxy TLS termination.
--
-- Public WSS TLS moves to Apache (`app`); Asterisk serves private plain WS
-- on the Docker network at 0.0.0.0:8088 (never host-published). Clear
-- Asterisk-side HTTP cert references on the seeded websocket row so
-- senma-http-tls.conf emits tlsenable=no. Native SIP TLS (protocol=tls)
-- rows are untouched. Idempotent: only the known seed row shape is updated.
UPDATE pjsip_transports
SET protocol = 'ws',
    bind_port = 8088,
    cert_file = NULL,
    priv_key_file = NULL
WHERE name = 'wss'
  AND is_seed = 1
  AND (
        protocol = 'wss'
     OR bind_port = 8089
     OR (cert_file IS NOT NULL AND cert_file != '')
  );
