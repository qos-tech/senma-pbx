/* SENMA TASK-0035C disposable browser harness (JsSIP). Not production UI. */
(function () {
  "use strict";

  const logEl = document.getElementById("log");
  const remoteAudio = document.getElementById("remoteAudio");

  /** @type {any} */
  window.__SENMA_RESULT__ = {
    phase: "init",
    registerOk: false,
    callOk: false,
    mediaOk: false,
    inboundInvite: false,
    hangupOk: false,
    errors: [],
    ice: {
      localTypes: [],
      remoteTypes: [],
      selected: null,
      bytesSent: 0,
      bytesReceived: 0,
      packetsSent: 0,
      packetsReceived: 0,
      codec: null,
      dtlsState: null,
      iceState: null,
      connectionState: null,
    },
    events: [],
  };

  function log(msg) {
    const line = "[" + new Date().toISOString() + "] " + msg;
    logEl.textContent += line + "\n";
    window.__SENMA_RESULT__.events.push(line);
  }

  function fail(msg) {
    window.__SENMA_RESULT__.errors.push(msg);
    log("ERROR: " + msg);
  }

  function classifyCandidate(cand) {
    if (!cand) return null;
    // typ host / srflx / relay / prflx
    const m = / typ ([a-z0-9]+)/.exec(cand);
    return m ? m[1] : "unknown";
  }

  function sanitizeSdp(sdp) {
    if (!sdp) return "";
    return String(sdp)
      .replace(/a=fingerprint:.*$/gm, "a=fingerprint:[redacted]")
      .replace(/a=ice-ufrag:.*$/gm, "a=ice-ufrag:[redacted]")
      .replace(/a=ice-pwd:.*$/gm, "a=ice-pwd:[redacted]")
      .replace(/a=crypto:.*$/gm, "a=crypto:[redacted]");
  }

  let ua = null;
  let session = null;
  let statsTimer = null;

  async function collectStats(pc) {
    if (!pc) return;
    const result = window.__SENMA_RESULT__.ice;
    result.connectionState = pc.connectionState || null;
    result.iceState = pc.iceConnectionState || null;
    try {
      const stats = await pc.getStats();
      const localTypes = new Set();
      const remoteTypes = new Set();
      let selected = null;
      let bytesSent = 0;
      let bytesReceived = 0;
      let packetsSent = 0;
      let packetsReceived = 0;
      let codec = null;
      let dtlsState = null;

      const byId = {};
      stats.forEach((r) => {
        byId[r.id] = r;
      });

      stats.forEach((r) => {
        if (r.type === "local-candidate" && r.candidateType) localTypes.add(r.candidateType);
        if (r.type === "remote-candidate" && r.candidateType) remoteTypes.add(r.candidateType);
        if (r.type === "transport" && r.dtlsState) dtlsState = r.dtlsState;
        if (r.type === "outbound-rtp" && r.kind === "audio") {
          bytesSent += r.bytesSent || 0;
          packetsSent += r.packetsSent || 0;
          if (r.codecId && byId[r.codecId] && byId[r.codecId].mimeType) {
            codec = byId[r.codecId].mimeType;
          }
        }
        if (r.type === "inbound-rtp" && r.kind === "audio") {
          bytesReceived += r.bytesReceived || 0;
          packetsReceived += r.packetsReceived || 0;
          if (!codec && r.codecId && byId[r.codecId] && byId[r.codecId].mimeType) {
            codec = byId[r.codecId].mimeType;
          }
        }
        if (
          (r.type === "candidate-pair" && (r.selected || r.nominated) && r.state === "succeeded") ||
          (r.type === "transport" && r.selectedCandidatePairId)
        ) {
          const pair =
            r.type === "candidate-pair"
              ? r
              : byId[r.selectedCandidatePairId];
          if (pair && pair.localCandidateId && pair.remoteCandidateId) {
            const local = byId[pair.localCandidateId];
            const remote = byId[pair.remoteCandidateId];
            selected = {
              localType: local && local.candidateType ? local.candidateType : null,
              remoteType: remote && remote.candidateType ? remote.candidateType : null,
              localProtocol: local && local.protocol ? local.protocol : null,
              remoteProtocol: remote && remote.protocol ? remote.protocol : null,
              // Addresses are topology evidence; keep host/port shape only.
              localAddressClass: local && local.address ? addressClass(local.address) : null,
              remoteAddressClass: remote && remote.address ? addressClass(remote.address) : null,
            };
          }
        }
      });

      result.localTypes = Array.from(localTypes).sort();
      result.remoteTypes = Array.from(remoteTypes).sort();
      if (selected) result.selected = selected;
      result.bytesSent = bytesSent;
      result.bytesReceived = bytesReceived;
      result.packetsSent = packetsSent;
      result.packetsReceived = packetsReceived;
      if (codec) result.codec = codec;
      if (dtlsState) result.dtlsState = dtlsState;

      if (
        bytesSent > 0 &&
        bytesReceived > 0 &&
        (dtlsState === "connected" || result.connectionState === "connected")
      ) {
        window.__SENMA_RESULT__.mediaOk = true;
        window.__SENMA_RESULT__.callOk = true;
        window.__SENMA_RESULT__.phase = "media_ok";
      }
    } catch (e) {
      fail("getStats: " + (e && e.message ? e.message : String(e)));
    }
  }

  function addressClass(addr) {
    if (!addr) return null;
    if (addr === "127.0.0.1" || addr === "::1") return "loopback";
    if (/^10\.|^192\.168\.|^172\.(1[6-9]|2\d|3[0-1])\./.test(addr)) return "private";
    if (addr.indexOf(":") >= 0) return "ipv6";
    return "public_or_other";
  }

  function attachSession(s) {
    session = s;
    document.getElementById("btnHangup").disabled = false;
    document.getElementById("btnCall").disabled = true;

    s.on("peerconnection", function (e) {
      const pc = e.peerconnection;
      log("peerconnection created");
      pc.addEventListener("icecandidate", function (ev) {
        if (ev.candidate && ev.candidate.candidate) {
          const t = classifyCandidate(ev.candidate.candidate);
          log("local ICE candidate typ=" + t);
        }
      });
      pc.addEventListener("iceconnectionstatechange", function () {
        log("iceConnectionState=" + pc.iceConnectionState);
        window.__SENMA_RESULT__.ice.iceState = pc.iceConnectionState;
      });
      pc.addEventListener("connectionstatechange", function () {
        log("connectionState=" + pc.connectionState);
        window.__SENMA_RESULT__.ice.connectionState = pc.connectionState;
      });
      pc.addEventListener("track", function (ev) {
        log("remote track kind=" + (ev.track && ev.track.kind));
        if (ev.streams && ev.streams[0]) {
          remoteAudio.srcObject = ev.streams[0];
        }
      });
      if (statsTimer) clearInterval(statsTimer);
      statsTimer = setInterval(function () {
        collectStats(pc);
      }, 1000);
    });

    s.on("accepted", function () {
      log("session accepted");
      window.__SENMA_RESULT__.phase = "accepted";
      if (s.connection) {
        log("local SDP sanitized excerpt:\n" + sanitizeSdp(s.connection.localDescription && s.connection.localDescription.sdp).split("\n").filter(function (l) {
          return /^(m=audio|a=rtpmap|a=fingerprint|a=candidate|a=ice-|c=IN)/.test(l);
        }).slice(0, 40).join("\n"));
      }
    });

    s.on("confirmed", function () {
      log("session confirmed");
      window.__SENMA_RESULT__.callOk = true;
      window.__SENMA_RESULT__.phase = "confirmed";
    });

    s.on("ended", function () {
      log("session ended");
      window.__SENMA_RESULT__.hangupOk = true;
      document.getElementById("btnHangup").disabled = true;
      document.getElementById("btnCall").disabled = !window.__SENMA_RESULT__.registerOk;
      if (statsTimer) {
        clearInterval(statsTimer);
        statsTimer = null;
      }
    });

    s.on("failed", function (e) {
      fail("session failed: " + (e && e.cause ? e.cause : "unknown"));
      window.__SENMA_RESULT__.phase = "call_failed";
    });
  }

  function doRegister() {
    const JsSIP = window.JsSIP;
    if (!JsSIP) {
      fail("JsSIP bundle missing");
      return;
    }
    JsSIP.C.SESSION_EXPIRES = 120;
    const wssUrl = document.getElementById("wssUrl").value.trim();
    const sipUri = document.getElementById("sipUri").value.trim();
    const password = document.getElementById("password").value;
    const displayName = document.getElementById("displayName").value.trim();

    if (ua) {
      try { ua.stop(); } catch (_) { /* ignore */ }
      ua = null;
    }

    const socket = new JsSIP.WebSocketInterface(wssUrl);
    const configuration = {
      sockets: [socket],
      uri: sipUri,
      password: password,
      display_name: displayName,
      register: true,
      session_timers: false,
    };

    ua = new JsSIP.UA(configuration);
    window.__SENMA_UA__ = ua;
    window.__SENMA_RESULT__.phase = "registering";

    ua.on("connected", function () {
      log("WSS connected");
    });
    ua.on("disconnected", function () {
      log("WSS disconnected");
    });
    ua.on("registered", function () {
      log("REGISTER OK");
      window.__SENMA_RESULT__.registerOk = true;
      window.__SENMA_RESULT__.phase = "registered";
      document.getElementById("btnCall").disabled = false;
      document.getElementById("btnUnregister").disabled = false;
    });
    ua.on("unregistered", function () {
      log("unregistered");
      window.__SENMA_RESULT__.registerOk = false;
      document.getElementById("btnCall").disabled = true;
    });
    ua.on("registrationFailed", function (e) {
      fail("registrationFailed: " + (e && e.cause ? e.cause : "unknown"));
      window.__SENMA_RESULT__.phase = "register_failed";
    });
    ua.on("newRTCSession", function (e) {
      log("newRTCSession originator=" + e.originator);
      if (e.originator === "remote") {
        window.__SENMA_RESULT__.inboundInvite = true;
        // Auto-answer for inbound SIP→browser proof when requested.
        if (window.__SENMA_AUTO_ANSWER__) {
          e.session.answer({
            mediaConstraints: { audio: true, video: false },
            pcConfig: { iceServers: window.__SENMA_ICE_SERVERS__ || [] },
          });
          attachSession(e.session);
        } else {
          log("inbound INVITE received (auto-answer disabled)");
          attachSession(e.session);
        }
      }
    });

    ua.start();
    log("UA start -> " + wssUrl + " as " + sipUri);
  }

  function doCall() {
    if (!ua) {
      fail("UA not started");
      return;
    }
    const target = document.getElementById("target").value.trim();
    const eventHandlers = {};
    const options = {
      eventHandlers: eventHandlers,
      mediaConstraints: { audio: true, video: false },
      pcConfig: { iceServers: window.__SENMA_ICE_SERVERS__ || [] },
    };
    window.__SENMA_RESULT__.phase = "calling";
    log("INVITE -> " + target);
    const s = ua.call("sip:" + target + "@asterisk", options);
    attachSession(s);
  }

  function doHangup() {
    if (session) {
      try { session.terminate(); } catch (e) { fail(String(e)); }
    }
  }

  function doUnregister() {
    if (ua) {
      try { ua.unregister(); ua.stop(); } catch (e) { fail(String(e)); }
    }
  }

  document.getElementById("btnRegister").addEventListener("click", doRegister);
  document.getElementById("btnCall").addEventListener("click", doCall);
  document.getElementById("btnHangup").addEventListener("click", doHangup);
  document.getElementById("btnUnregister").addEventListener("click", doUnregister);

  // Automation hooks used by run.mjs / smoke harness.
  window.__SENMA_REGISTER__ = doRegister;
  window.__SENMA_CALL__ = doCall;
  window.__SENMA_HANGUP__ = doHangup;
  window.__SENMA_UNREGISTER__ = doUnregister;
  window.__SENMA_COLLECT__ = async function () {
    if (session && session.connection) await collectStats(session.connection);
    return window.__SENMA_RESULT__;
  };

  log("harness ready");
  window.__SENMA_RESULT__.phase = "ready";
})();
