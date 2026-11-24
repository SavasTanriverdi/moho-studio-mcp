#!/usr/bin/env node
// Zero-dependency Node.js 20+ stdio MCP server for Moho Studio MCP v3.0.0.

import fs from "node:fs";
import readline from "node:readline";
import { PROTOCOL_VERSION, SERVER_INFO, TIMEOUTS } from "./config.mjs";
import { MohoIpcClient } from "./ipc.mjs";
import { TOOLS, TOOL_BY_NAME } from "./tools.mjs";
import { PLAYBOOK_TEXT } from "./playbook.mjs";

const ipc = new MohoIpcClient();

const GUIDE_TEXT = [
  "# Moho Studio MCP v3.0.0 Quick Guide",
  "- Read `moho-studio://playbook` first for 15 Moho Pro 14.4 rigging, shading, animation, glTF, and Lua safety rules.",
  "- Start every live session with `moho_status` to confirm Moho Pro 14.4 connectivity.",
  "- Use `moho_apiInspect` (includes tolua++ `.get`/`.set` properties) before writing custom `lua_execute` scripts.",
  "- Use `batch_execute` for multi-bone, multi-layer, or multi-keyframe edits (single Undo step + coalesced UI refresh).",
  "- Use `document_renderFrame` for live visual checks (do not trust viewport captures alone for masks, Point Colors, Merged-Alpha brushes, or Bone Dynamics), `layer_renderImage` for isolated transparent PNGs, `document_cliRender` for headless GPU batch renders, and `rig_auditGltf` + `document_exportGltf` for headless glTF 2.0 / GLB exports.",
  "- Use `mesh_createSmartWarp` (`warp`, `quad`, `curver` + `compressible` + multi-curve), `mesh_editShape`, `mesh_editPoints`, `mesh_editTopology`, `mesh_setCurveProfile`, `mesh_liquidShapes`, and `style_manage` (Saved Styles, `new_from_shape`, Moho 14 Brushes + Smart Line Boil).",
  "- Use `action_createSmartBone` (standard and exact +/-360-deg turnarounds), `animation_createCycle`, `animation_retime`, `animation_tween`, `timeline_markers`, `fbf_manage`, `layer_setMasking`, `layer_setLayerOrder`, `bone_manageGroup` (Vitruvian Bones), `bone_mirror`, `bone_freezePose`, `bone_setWind`, `physics_configure`, `particle_configure`, and `layercomp_manage` for Moho Pro 14.4 workflows.",
].join("\n");

function writeJsonRpc(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

function sendResult(id, result) {
  writeJsonRpc({ jsonrpc: "2.0", id, result });
}

function sendError(id, code, message) {
  writeJsonRpc({ jsonrpc: "2.0", id, error: { code, message: String(message) } });
}

function resolveTimeout(toolDef) {
  if (toolDef.timeoutKind === "renderRange") return TIMEOUTS.renderRangeMs;
  if (toolDef.timeoutKind === "render") return TIMEOUTS.renderMs;
  if (toolDef.timeoutKind === "batch") return TIMEOUTS.batchMs;
  if (toolDef.timeoutKind === "lua") return TIMEOUTS.luaExecuteMs;
  return TIMEOUTS.defaultMs;
}

async function handleToolCall(name, args = {}) {
  const toolDef = TOOL_BY_NAME.get(name);
  if (!toolDef) {
    return {
      isError: true,
      content: [{ type: "text", text: `Unknown tool: ${name}` }],
    };
  }

  try {
    let result;
    if (toolDef.hostHandler === "captureWindow") {
      result = await ipc.captureWindow(args.outputPath);
    } else if (toolDef.hostHandler === "cliRender") {
      result = await ipc.cliRender(args);
    } else if (toolDef.hostHandler === "activatePoller") {
      result = await ipc.activatePoller();
    } else {
      result = await ipc.send(toolDef.rpcMethod, args, resolveTimeout(toolDef));
    }

    const content = [{ type: "text", text: JSON.stringify(result, null, 2) }];

    const wantImage = toolDef.returnsImage && (toolDef.defaultReturnImage === false ? args.returnImage === true : args.returnImage !== false);
    if (wantImage && result && result.outputPath && fs.existsSync(result.outputPath)) {
      const b64 = fs.readFileSync(result.outputPath).toString("base64");
      content.push({
        type: "image",
        data: b64,
        mimeType: "image/png",
      });
    }

    return { content };
  } catch (err) {
    return {
      isError: true,
      content: [{ type: "text", text: `Error in ${name}: ${err.message || String(err)}` }],
    };
  }
}

async function handleMessage(msg) {
  if (!msg || typeof msg !== "object" || !msg.method) {
    return;
  }
  const { id, method, params } = msg;

  if (id === undefined || id === null) {
    return;
  }

  try {
    if (method === "initialize") {
      sendResult(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {
          tools: {},
          resources: {},
        },
        serverInfo: SERVER_INFO,
      });
      return;
    }

    if (method === "ping") {
      sendResult(id, {});
      return;
    }

    if (method === "tools/list") {
      sendResult(id, {
        tools: TOOLS.map(({ name, description, inputSchema }) => ({
          name,
          description,
          inputSchema,
        })),
      });
      return;
    }

    if (method === "tools/call") {
      const toolName = params && params.name;
      const toolArgs = (params && params.arguments) || {};
      const out = await handleToolCall(toolName, toolArgs);
      sendResult(id, out);
      return;
    }

    if (method === "resources/list") {
      sendResult(id, {
        resources: [
          {
            uri: "moho-studio://guide",
            name: "Moho Studio MCP Guide",
            description: "Quick operational guide for live Moho Pro 14.4 automation (points to moho-studio://playbook)",
            mimeType: "text/markdown",
          },
          {
            uri: "moho-studio://playbook",
            name: "Moho Pro 14.4 Master Playbook",
            description: "15 distilled Moho Pro 14.4 rigging, vector shading, animation, and glTF master rules plus Lua engine invariants",
            mimeType: "text/markdown",
          },
        ],
      });
      return;
    }

    if (method === "resources/read") {
      if (params && params.uri === "moho-studio://guide") {
        sendResult(id, {
          contents: [
            {
              uri: "moho-studio://guide",
              mimeType: "text/markdown",
              text: GUIDE_TEXT,
            },
          ],
        });
        return;
      }
      if (params && params.uri === "moho-studio://playbook") {
        sendResult(id, {
          contents: [
            {
              uri: "moho-studio://playbook",
              mimeType: "text/markdown",
              text: PLAYBOOK_TEXT,
            },
          ],
        });
        return;
      }
      sendError(id, -32602, `Unknown resource URI: ${params && params.uri}`);
      return;
    }

    sendError(id, -32601, `Method not found: ${method}`);
  } catch (err) {
    sendError(id, -32603, err.message || String(err));
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let parsed;
  try {
    parsed = JSON.parse(trimmed);
  } catch (err) {
    sendError(null, -32700, `Parse error: ${err.message}`);
    return;
  }
  handleMessage(parsed).catch((err) => {
    process.stderr.write(`[moho-studio-mcp] Unhandled error: ${err.stack || err}\n`);
  });
});

function shutdown() {
  ipc.stopKeepAlive();
  process.exit(0);
}

rl.on("close", shutdown);
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
