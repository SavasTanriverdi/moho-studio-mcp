import os from "node:os";
import path from "node:path";

export const SERVER_INFO = {
  name: "moho-studio-mcp",
  version: "3.0.0",
};

export const PROTOCOL_VERSION = "2024-11-05";

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
