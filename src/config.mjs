import os from "node:os";
import path from "node:path";

export const SERVER_INFO = {
  name: "moho-studio-mcp",
  version: "3.1.0",
};

export const PROTOCOL_VERSION = "2025-03-26";
export const SUPPORTED_PROTOCOL_VERSIONS = ["2025-03-26", "2024-11-05"];
export const TOOL_PROFILES = ["full", "core", "rigging", "animation", "vector"];

export function negotiateProtocolVersion(clientVersion) {
  if (typeof clientVersion === "string" && SUPPORTED_PROTOCOL_VERSIONS.includes(clientVersion)) {
    return clientVersion;
  }
  return PROTOCOL_VERSION;
}

export function resolveToolProfile(cliProfile) {
  const raw = (cliProfile || process.env.MOHO_STUDIO_TOOLS || "full").trim().toLowerCase();
  if (TOOL_PROFILES.includes(raw)) {
    return raw;
  }
  return "full";
}

export function getIpcDir() {
  const override = process.env.MOHO_STUDIO_IPC_DIR;
  if (override && override.trim().length > 0) {
    return path.resolve(override.trim());
  }
  return path.join(os.tmpdir(), "moho-studio-mcp");
}

export const TIMEOUTS = {
  pollIntervalMs: 35,
  defaultMs: 15_000,
  renderMs: 60_000,
  renderRangeMs: 180_000,
  batchMs: 60_000,
  luaExecuteMs: 30_000,
};
