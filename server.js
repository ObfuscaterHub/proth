const express = require("express");
const compression = require("compression");
const multer = require("multer");
const { execFile } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const LUA_SRC_DIR = path.join(__dirname, "lua-src");
const LOCAL_LUA_BIN = path.join(__dirname, "vendor", "bin", "lua5.1");
const LUA_BIN = fs.existsSync(LOCAL_LUA_BIN) ? LOCAL_LUA_BIN : "lua5.1";

const CACHE_MAX_ENTRIES = parseInt(process.env.CACHE_MAX_ENTRIES || "40", 10);

const JOB_TIMEOUT_MS = parseInt(process.env.JOB_TIMEOUT_MS || "300000", 10);

const MAX_OOM_RETRIES = parseInt(process.env.MAX_OOM_RETRIES || "3", 10);
const OOM_RETRY_DELAY_MS = parseInt(process.env.OOM_RETRY_DELAY_MS || "500", 10);

app.use(compression());
app.use(express.json({ limit: "10mb" }));
app.use(express.static(path.join(__dirname, "public")));

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

const VALID_PRESETS = ["Minify", "Weak", "Medium", "Strong", "Ultra"];

const ANSI_PATTERN = /\x1b\[[0-9;]*m/g;

function extractCleanError(rawStderr, rawStdout, fallbackMessage) {
  const raw = (rawStderr || rawStdout || fallbackMessage || "Obfuscation failed.").toString();
  const clean = raw.replace(ANSI_PATTERN, "");

  const lines = clean.split("\n").map((l) => l.trim()).filter(Boolean);
  for (let i = lines.length - 1; i >= 0; i--) {
    if (lines[i].startsWith("PROMETHEUS:") && /error/i.test(lines[i])) {
      return lines[i].replace(/^PROMETHEUS:\s*/, "");
    }
  }

  const isTraceLine = (l) =>
    l.startsWith("stack traceback") || l.startsWith("[C]:") || l.startsWith("./") || /:\d+:\s*in function/.test(l);
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!isTraceLine(lines[i])) {
      return lines[i];
    }
  }
  return lines[0] || "Obfuscation failed.";
}

const MAX_CONCURRENT_JOBS = parseInt(process.env.MAX_CONCURRENT_JOBS || "3", 10);

class JobQueue {
  constructor(maxConcurrent) {
    this.maxConcurrent = Math.max(1, maxConcurrent);
    this.active = 0;
    this.waiting = [];
  }

  get queued() {
    return this.waiting.length;
  }

  run(task) {
    return new Promise((resolve, reject) => {
      const attempt = () => {
        this.active++;
        task()
          .then((result) => {
            this.active--;
            this._next();
            resolve(result);
          })
          .catch((err) => {
            this.active--;
            this._next();
            reject(err);
          });
      };

      if (this.active < this.maxConcurrent) {
        attempt();
      } else {
        this.waiting.push(attempt);
      }
    });
  }

  _next() {
    if (this.waiting.length > 0 && this.active < this.maxConcurrent) {
      const next = this.waiting.shift();
      next();
    }
  }
}

const jobQueue = new JobQueue(MAX_CONCURRENT_JOBS);

const resultCache = new Map();

function cacheKey(code, preset) {
  return crypto.createHash("sha256").update(preset).update("\0").update(code).digest("hex");
}

function cacheGet(key) {
  if (!resultCache.has(key)) return undefined;
  const value = resultCache.get(key);
  resultCache.delete(key);
  resultCache.set(key, value);
  return value;
}

function cacheSet(key, value) {
  resultCache.set(key, value);
  if (resultCache.size > CACHE_MAX_ENTRIES) {
    const oldestKey = resultCache.keys().next().value;
    resultCache.delete(oldestKey);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function runObfuscation(sourceCode, preset, onChild) {
  return new Promise((resolve, reject) => {
    const args = ["prometheus-main.lua", "--preset", preset, "--out", "-", "-"];

    const child = execFile(
      LUA_BIN,
      args,
      { cwd: LUA_SRC_DIR, timeout: JOB_TIMEOUT_MS, maxBuffer: 100 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) {
          if (err.killed && err.signal === "SIGTERM") {
            return reject(new Error("Obfuscation was cancelled or timed out."));
          }
          if (err.killed || err.signal) {
            console.error(`Obfuscation child killed by signal ${err.signal} (likely out of memory)`);
            const oomErr = new Error("Obfuscation was interrupted (server ran low on memory). Please try again.");
            oomErr.isOom = true;
            return reject(oomErr);
          }
          return reject(new Error(extractCleanError(stderr, stdout, err.message)));
        }
        if (!stdout) {
          return reject(new Error(extractCleanError(stderr, stdout, "Obfuscator did not produce output.")));
        }
        resolve(stdout);
      }
    );

    if (typeof onChild === "function") onChild(child);

    child.stdin.on("error", () => {});
    child.stdin.write(sourceCode);
    child.stdin.end();
  });
}

async function runObfuscationWithRetry(code, preset, getActiveChild, isClientGone) {
  let lastErr = null;

  for (let attempt = 1; attempt <= MAX_OOM_RETRIES; attempt++) {
    if (isClientGone()) throw lastErr || new Error("Client disconnected.");

    try {
      const result = await jobQueue.run(() =>
        runObfuscation(code, preset, (child) => {
          getActiveChild(child);
          if (isClientGone()) child.kill("SIGKILL");
        })
      );
      return result;
    } catch (err) {
      lastErr = err;
      if (!err.isOom || attempt === MAX_OOM_RETRIES) {
        throw err;
      }
      console.error(`OOM on attempt ${attempt}/${MAX_OOM_RETRIES}, retrying...`);
      await sleep(OOM_RETRY_DELAY_MS);
    }
  }

  throw lastErr;
}

app.post("/api/obfuscate", upload.none(), async (req, res) => {
  let activeChild = null;
  let clientGone = false;

  const onClientClose = () => {
    if (res.writableEnded) return;
    clientGone = true;
    if (activeChild) {
      activeChild.kill("SIGKILL");
    }
  };
  res.on("close", onClientClose);

  try {
    const { code, preset } = req.body;

    if (!code || typeof code !== "string" || !code.trim()) {
      return res.status(400).json({ error: "No script provided." });
    }
    if (code.length > 10 * 1024 * 1024) {
      return res.status(400).json({ error: "Script is too large (max 10MB)." });
    }
    if (!VALID_PRESETS.includes(preset)) {
      return res.status(400).json({ error: "Invalid preset." });
    }

    const key = cacheKey(code, preset);
    const cached = cacheGet(key);
    if (cached !== undefined) {
      return res.json({ output: cached, cached: true });
    }

    const tQueueStart = Date.now();

    const result = await runObfuscationWithRetry(
      code,
      preset,
      (child) => {
        activeChild = child;
      },
      () => clientGone
    );

    const tJobEnd = Date.now();
    const totalMs = tJobEnd - tQueueStart;

    if (clientGone) return;

    cacheSet(key, result);
    res.set("X-Processing-Time", String(totalMs));
    res.json({ output: result, cached: false, totalMs });
  } catch (err) {
    if (clientGone) return;
    const message = err.message || "Obfuscation failed.";
    if (/low on memory/i.test(message)) {
      return res.status(503).json({ error: message, type: "out_of_memory" });
    }
    const type = /Parsing Error/i.test(message) ? "syntax_error" : "obfuscation_error";
    res.status(400).json({ error: message, type });
  } finally {
    res.off("close", onClientClose);
  }
});

app.get("/api/health", (req, res) =>
  res.json({
    ok: true,
    activeJobs: jobQueue.active,
    queuedJobs: jobQueue.queued,
    maxConcurrentJobs: jobQueue.maxConcurrent,
    maxOomRetries: MAX_OOM_RETRIES,
    cacheSize: resultCache.size,
    cacheMaxEntries: CACHE_MAX_ENTRIES,
  })
);

app.listen(PORT, () => {
  console.log(`Prometheus web UI running on port ${PORT}`);
  console.log(`Max concurrent obfuscation jobs: ${MAX_CONCURRENT_JOBS}`);
  console.log(`Max OOM retries: ${MAX_OOM_RETRIES}`);
  console.log(`Result cache size: ${CACHE_MAX_ENTRIES}`);
});
