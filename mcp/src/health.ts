import { accessSync, constants as FS, statSync } from "node:fs";
import { delimiter, join } from "node:path";
import { config } from "./config.js";

export type CheckStatus = "ok" | "warn" | "fail";
export interface HealthCheck {
  name: string;
  status: CheckStatus;
  value: string;
  detail: string;
  configuredByEnv: boolean;
}
export interface HealthReport {
  checks: HealthCheck[];
  overall: CheckStatus;
  psycheAvailable: boolean;
  retrievalAvailable: boolean;
  fatal: boolean;
  exitWorthy: boolean;
  at: string;
}

export function isExecutableFile(p: string): boolean {
  try { accessSync(p, FS.X_OK); return statSync(p).isFile(); } catch { return false; }
}
export function isReadableDir(p: string): boolean {
  try { accessSync(p, FS.R_OK); return statSync(p).isDirectory(); } catch { return false; }
}
export function isReadableFile(p: string): boolean {
  try { accessSync(p, FS.R_OK); return statSync(p).isFile(); } catch { return false; }
}

/** Resolve a command: an absolute/relative path is checked directly; a bare
 *  name is scanned against PATH (matching the two real GBRAIN_CMD forms). */
export function resolveCommand(cmd: string): string | null {
  if (cmd.includes("/")) return isExecutableFile(cmd) ? cmd : null;
  for (const dir of (process.env.PATH ?? "").split(delimiter)) {
    if (dir && isExecutableFile(join(dir, cmd))) return join(dir, cmd);
  }
  return null;
}

function hasSelfPage(dir: string): boolean {
  return isReadableFile(join(dir, "people-david.md")) || isReadableFile(join(dir, "people", "david.md"));
}

let _retrievalMemo: boolean | null = null;
/** Cheap gate the retrieval hot-path checks before spawning gbrain. */
export function isRetrievalConfigured(force = false): boolean {
  if (_retrievalMemo === null || force) {
    _retrievalMemo = resolveCommand(config.gbrainCmd) !== null && isReadableDir(config.gbrainSourceDir);
  }
  return _retrievalMemo;
}

/** Validate the whole configuration. Warns on missing DEFAULT paths (graceful
 *  degradation) but FAILs on an explicitly env-set broken path (operator typo),
 *  and only asks to exit when nothing at all is usable (or strict mode). */
export function validateConfig(refresh = true): HealthReport {
  const checks: HealthCheck[] = [];

  const cmdEnv = process.env.GBRAIN_CMD != null;
  const cmdResolved = resolveCommand(config.gbrainCmd);
  checks.push({
    name: "gbrainCmd", value: config.gbrainCmd, configuredByEnv: cmdEnv,
    status: cmdResolved ? "ok" : (cmdEnv ? "fail" : "warn"),
    detail: cmdResolved
      ? `executable (${cmdResolved})`
      : (cmdEnv ? "GBRAIN_CMD set but not executable/on PATH — retrieval OFF"
                : "gbrain command not found — retrieval OFF, identity still works"),
  });

  const dirEnv = process.env.GBRAIN_SOURCE_DIR != null;
  const dirOk = isReadableDir(config.gbrainSourceDir);
  checks.push({
    name: "gbrainSourceDir", value: config.gbrainSourceDir, configuredByEnv: dirEnv,
    status: dirOk ? "ok" : (dirEnv ? "fail" : "warn"),
    detail: dirOk
      ? (hasSelfPage(config.gbrainSourceDir) ? "readable (self-page present)" : "readable (no self-page — psyche fallback thin)")
      : "not a readable directory — page reads + psyche fallback OFF",
  });

  const psyEnv = process.env.GLIA_PSYCHE != null;
  const psyOk = isReadableFile(config.psycheFile);
  let psyStatus: CheckStatus, psyDetail: string;
  if (psyOk) { psyStatus = "ok"; psyDetail = "canonical Glia export present"; }
  else if (dirOk && hasSelfPage(config.gbrainSourceDir)) { psyStatus = "warn"; psyDetail = "no Glia export — will build psyche from gbrain source"; }
  else { psyStatus = psyEnv ? "fail" : "warn"; psyDetail = "no psyche file and no source self-page — identity UNAVAILABLE"; }
  checks.push({ name: "psyche", value: config.psycheFile, configuredByEnv: psyEnv, status: psyStatus, detail: psyDetail });

  if (refresh) isRetrievalConfigured(true);
  const retrievalAvailable = cmdResolved !== null && dirOk;
  const psycheAvailable = psyOk || (dirOk && hasSelfPage(config.gbrainSourceDir));
  const overall = checks.reduce<CheckStatus>(
    (w, c) => c.status === "fail" ? "fail" : (c.status === "warn" && w === "ok" ? "warn" : w), "ok");
  const fatal = !psycheAvailable && !retrievalAvailable;
  const exitWorthy = fatal || (config.strictStartup && checks.some((c) => c.status === "fail"));
  return { checks, overall, psycheAvailable, retrievalAvailable, fatal, exitWorthy, at: new Date().toISOString() };
}

export function renderHealthReport(r: HealthReport): string {
  const icon = (s: CheckStatus) => s === "ok" ? "OK  " : s === "warn" ? "WARN" : "FAIL";
  const lines = [
    `glia-context health @ ${r.at}`,
    `  overall: ${r.overall.toUpperCase()} | identity: ${r.psycheAvailable ? "available" : "UNAVAILABLE"} | retrieval: ${r.retrievalAvailable ? "available" : "OFF"}`,
    ...r.checks.map((c) => `  [${icon(c.status)}] ${c.name}: ${c.detail}\n           ${c.value}`),
  ];
  if (r.fatal) lines.push("  FATAL: neither identity nor retrieval usable — check GBRAIN_SOURCE_DIR / GLIA_PSYCHE / GBRAIN_CMD.");
  return lines.join("\n");
}
