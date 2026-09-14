#!/usr/bin/env node
/**
 * TASK-0035C — headless Chromium driver for the disposable JsSIP harness.
 *
 * Speaks only to the static harness + public WSS URL. Never embeds
 * production secrets; credentials come from env/CLI.
 *
 * Exit 0 on MEDIA_OK (or REGISTER_ONLY when --register-only), else 1.
 */
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = __dirname;
  const server = await serveStatic(root, args.listenPort || 0);
  const pageUrl = `http://127.0.0.1:${server.address().port}/index.html`;

  const puppeteer = require("puppeteer-core");
  const executablePath =
    process.env.CHROME_PATH ||
    args.chrome ||
    "/usr/bin/google-chrome-stable";

  const browser = await puppeteer.launch({
    executablePath,
    headless: args.headless === false ? false : true,
    args: [
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--use-fake-ui-for-media-stream",
      "--use-fake-device-for-media-stream",
      "--autoplay-policy=no-user-gesture-required",
      "--ignore-certificate-errors",
      "--allow-insecure-localhost",
    ],
  });

  const page = await browser.newPage();
  page.on("console", (msg) => {
    if (args.verbose) process.stderr.write(`[browser] ${msg.text()}\n`);
  });

  await page.goto(pageUrl, { waitUntil: "domcontentloaded", timeout: 30000 });

  await page.evaluate(
    (cfg) => {
      document.getElementById("wssUrl").value = cfg.wssUrl;
      document.getElementById("sipUri").value = cfg.sipUri;
      document.getElementById("password").value = cfg.password;
      document.getElementById("target").value = cfg.target;
      document.getElementById("displayName").value = cfg.displayName;
      window.__SENMA_AUTO_ANSWER__ = !!cfg.autoAnswer;
      window.__SENMA_ICE_SERVERS__ = cfg.iceServers || [];
    },
    {
      wssUrl: args.wssUrl,
      sipUri: args.sipUri,
      password: args.password,
      target: args.target,
      displayName: args.displayName || "senma-browser-harness",
      autoAnswer: !!args.autoAnswer,
      iceServers: args.iceServers || [],
    }
  );

  await page.evaluate(() => window.__SENMA_REGISTER__());
  const registered = await waitFor(
    page,
    () => window.__SENMA_RESULT__.registerOk === true || window.__SENMA_RESULT__.phase === "register_failed",
    args.registerTimeoutMs || 20000
  );

  let result = await page.evaluate(() => window.__SENMA_RESULT__);
  if (!result.registerOk) {
    await finish(browser, server, result, 1, "REGISTER_FAIL");
    return;
  }

  if (args.registerOnly) {
    if (args.holdMs) await sleep(args.holdMs);
    await page.evaluate(() => window.__SENMA_UNREGISTER__());
    result = await page.evaluate(() => window.__SENMA_COLLECT__());
    await finish(browser, server, result, 0, "REGISTER_OK");
    return;
  }

  if (args.waitInbound) {
    const inbound = await waitFor(
      page,
      () => window.__SENMA_RESULT__.inboundInvite === true || window.__SENMA_RESULT__.mediaOk === true,
      args.inboundTimeoutMs || 45000
    );
    result = await page.evaluate(() => window.__SENMA_COLLECT__());
    if (!result.inboundInvite && !result.mediaOk) {
      await finish(browser, server, result, 1, "INBOUND_TIMEOUT");
      return;
    }
  } else {
    await page.evaluate(() => window.__SENMA_CALL__());
  }

  const mediaOk = await waitFor(
    page,
    () => window.__SENMA_RESULT__.mediaOk === true || window.__SENMA_RESULT__.phase === "call_failed",
    args.mediaTimeoutMs || 45000
  );

  // Extra settle for RTP counters.
  await sleep(args.mediaSettleMs || 4000);
  result = await page.evaluate(() => window.__SENMA_COLLECT__());
  // Snapshot media counters before hangup tears down the PeerConnection.
  const preHangup = JSON.parse(JSON.stringify(result));

  if (args.hangup !== false) {
    await page.evaluate(() => window.__SENMA_HANGUP__());
    await sleep(1000);
    const after = await page.evaluate(() => window.__SENMA_COLLECT__());
    // Prefer pre-hangup media counters when post-hangup stats are zeroed.
    if ((after.ice.bytesSent || 0) === 0 && (preHangup.ice.bytesSent || 0) > 0) {
      after.ice.bytesSent = preHangup.ice.bytesSent;
      after.ice.bytesReceived = preHangup.ice.bytesReceived;
      after.ice.packetsSent = preHangup.ice.packetsSent;
      after.ice.packetsReceived = preHangup.ice.packetsReceived;
      after.ice.selected = after.ice.selected || preHangup.ice.selected;
      after.ice.dtlsState = after.ice.dtlsState || preHangup.ice.dtlsState;
      after.ice.codec = after.ice.codec || preHangup.ice.codec;
      after.mediaOk = after.mediaOk || preHangup.mediaOk;
      after.callOk = after.callOk || preHangup.callOk;
    }
    result = after;
  }

  const code = result.mediaOk ? 0 : 1;
  await finish(browser, server, result, code, result.mediaOk ? "MEDIA_OK" : "MEDIA_FAIL");
}

function parseArgs(argv) {
  const out = {
    wssUrl: process.env.WSS_URL || "wss://127.0.0.1:8443/asterisk/ws",
    sipUri: process.env.SIP_URI || "",
    password: process.env.SIP_PASSWORD || "",
    target: process.env.TARGET_EXT || "",
    displayName: process.env.DISPLAY_NAME || "senma-browser-harness",
    registerOnly: false,
    waitInbound: false,
    autoAnswer: false,
    hangup: true,
    headless: true,
    verbose: false,
    iceServers: [],
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case "--wss-url": out.wssUrl = next(); break;
      case "--sip-uri": out.sipUri = next(); break;
      case "--password": out.password = next(); break;
      case "--target": out.target = next(); break;
      case "--display-name": out.displayName = next(); break;
      case "--chrome": out.chrome = next(); break;
      case "--listen-port": out.listenPort = Number(next()); break;
      case "--register-only": out.registerOnly = true; break;
      case "--wait-inbound": out.waitInbound = true; out.autoAnswer = true; break;
      case "--auto-answer": out.autoAnswer = true; break;
      case "--no-hangup": out.hangup = false; break;
      case "--headed": out.headless = false; break;
      case "--verbose": out.verbose = true; break;
      case "--hold-ms": out.holdMs = Number(next()); break;
      case "--register-timeout-ms": out.registerTimeoutMs = Number(next()); break;
      case "--media-timeout-ms": out.mediaTimeoutMs = Number(next()); break;
      case "--inbound-timeout-ms": out.inboundTimeoutMs = Number(next()); break;
      case "--media-settle-ms": out.mediaSettleMs = Number(next()); break;
      case "--ice-server": {
        // e.g. stun:stun.l.google.com:19302  (optional; default none)
        const urls = next();
        out.iceServers.push({ urls });
        break;
      }
      case "--result-file": out.resultFile = next(); break;
      default:
        throw new Error("unknown arg: " + a);
    }
  }
  if (!out.sipUri || !out.password) throw new Error("--sip-uri and --password are required");
  if (!out.registerOnly && !out.waitInbound && !out.target) {
    throw new Error("--target is required unless --register-only or --wait-inbound");
  }
  return out;
}

function serveStatic(root, port) {
  const mime = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
  };
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const rel = decodeURIComponent((req.url || "/").split("?")[0]);
      const safe = path.normalize(rel).replace(/^(\.\.[/\\])+/, "");
      const filePath = path.join(root, safe === path.sep ? "index.html" : safe);
      if (!filePath.startsWith(root)) {
        res.writeHead(403);
        res.end("forbidden");
        return;
      }
      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(404);
          res.end("not found");
          return;
        }
        res.writeHead(200, { "Content-Type": mime[path.extname(filePath)] || "application/octet-stream" });
        res.end(data);
      });
    });
    server.listen(port, "127.0.0.1", () => resolve(server));
    server.on("error", reject);
  });
}

async function waitFor(page, fn, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const ok = await page.evaluate(fn);
    if (ok) return true;
    await sleep(250);
  }
  return false;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function finish(browser, server, result, code, label) {
  const payload = JSON.stringify({ label, result }, null, 2);
  process.stdout.write(payload + "\n");
  const outFile = process.env.RESULT_FILE;
  if (outFile) fs.writeFileSync(outFile, payload);
  try { await browser.close(); } catch (_) {}
  try { server.close(); } catch (_) {}
  process.exit(code);
}

main().catch((err) => {
  process.stderr.write(String(err && err.stack ? err.stack : err) + "\n");
  process.exit(2);
});
