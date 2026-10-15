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

// How many lua5.1 obfuscation processes are allowed to run at the same time.
// This is the single most important knob for memory safety: each running
// job can use anywhere from ~30MB (Minify/Weak) to 700MB+ (Ultra), and they
// are NOT capped individually - they're capped by how many can exist at
// once. Extra requests beyond this limit are queued (FIFO), not rejected,
// so rapid repeated calls stay fast and safe instead of piling up memory.
// Tune this down (1) on very memory-constrained hosts (e.g. Suga Free's
// 256MB), or up on a bigger box.
const MAX_CONCURRENT_JOBS = parseInt(process.env.MAX_CONCURRENT_JOBS || "2", 10);

// How many most-recent distinct (code, preset) results to keep in memory.
// A cache hit skips spawning lua5.1 entirely and returns in well under a
// millisecond, which is what makes *repeated* identical requests fast -
// re-clicking "Obfuscate" on the same script/preset, or a client retrying
// after a network hiccup, no longer costs a full obfuscation run.
const CACHE_MAX_ENTRIES = parseInt(process.env.CACHE_MAX_ENTRIES || "40", 10);

// Hard ceiling per job, independent of how long the queue in front of it is.
const JOB_TIMEOUT_MS = parseInt(process.env.JOB_TIMEOUT_MS || "300000", 10);

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

// --- Tiny FIFO concurrency queue ------------------------------------------
// No external dependency: a fixed number of "slots" are handed out in
// request order. A job that can't get a slot immediately waits in line;
// whoever finishes first hands their slot to the next person waiting.
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

// --- Tiny FIFO result cache ------------------------------------------------
// Keyed by a hash of (preset + code), so re-submitting the exact same
// script+preset - the common case when someone is iterating/retrying -
// never touches lua5.1 at all.
const resultCache = new Map(); // key -> output string

function cacheKey(code, preset) {
  return crypto.createHash("sha256").update(preset).update("\0").update(code).digest("hex");
}

function cacheGet(key) {
  if (!resultCache.has(key)) return undefined;
  const value = resultCache.get(key);
  // refresh recency: delete + re-set moves it to the end of Map's
  // iteration order, which we use as our eviction order below.
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

// --- Obfuscation runner ----------------------------------------------------
function runObfuscation(sourceCode, preset, onChild) {
  return new Promise((resolve, reject) => {
    const args = ["prometheus-main.lua", "--preset", preset, "--out", "-", "-"];

    const child = execFile(
      LUA_BIN,
      args,
      { cwd: LUA_SRC_DIR, timeout: JOB_TIMEOUT_MS, maxBuffer: 100 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) {
          if (err.killed || err.signal) {
            return reject(new Error("Obfuscation was cancelled or timed out."));
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

    child.stdin.on("error", () => {}); // avoid unhandled EPIPE if the process exits early on bad input
    child.stdin.write(sourceCode);
    child.stdin.end();
  });
}

app.post("/api/obfuscate", upload.none(), async (req, res) => {
  let activeChild = null;
  let clientGone = false;

  // Note: req's own "close" event fires as soon as the incoming request
  // body has been fully read, which happens almost immediately - it does
  // NOT mean the client went away. res's "close" event is what actually
  // reflects "the client disconnected before we could respond", so that's
  // what we watch to decide whether to abort the in-flight job.
  const onClientClose = () => {
    if (res.writableEnded) return; // we already responded; this is a normal close
    clientGone = true;
    if (activeChild) {
      // The requester went away (closed tab, retried, aborted) - no point
      // burning CPU/RAM finishing an obfuscation nobody will read.
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

    const result = await jobQueue.run(() =>
      runObfuscation(code, preset, (child) => {
        activeChild = child;
        if (clientGone) child.kill("SIGKILL");
      })
    );

    if (clientGone) return; // nobody listening anymore, don't bother writing a response

    cacheSet(key, result);
    res.json({ output: result, cached: false });
  } catch (err) {
    if (clientGone) return;
    const message = err.message || "Obfuscation failed.";
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
    cacheSize: resultCache.size,
    cacheMaxEntries: CACHE_MAX_ENTRIES,
  })
);

app.listen(PORT, () => {
  console.log(`Prometheus web UI running on port ${PORT}`);
  console.log(`Max concurrent obfuscation jobs: ${MAX_CONCURRENT_JOBS}`);
  console.log(`Result cache size: ${CACHE_MAX_ENTRIES}`);
});
