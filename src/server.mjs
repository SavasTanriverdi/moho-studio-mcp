#!/usr/bin/env node
// Zero-dependency Node.js 20+ stdio MCP server and setup CLI for Moho Studio MCP v3.1.0.

import fs from "node:fs";
import readline from "node:readline";
import {
  negotiateProtocolVersion,
  resolveToolProfile,
  SERVER_INFO,
  TIMEOUTS,
} from "./config.mjs";
import { MohoIpcClient } from "./ipc.mjs";
import { getToolsForProfile, TOOL_BY_NAME } from "./tools.mjs";
import { PLAYBOOK_TEXT } from "./playbook.mjs";
import { PROMPTS, PROMPT_BY_NAME } from "./prompts.mjs";

const CLI_SUBCOMMANDS = new Set(["install", "doctor", "--help", "-h", "--version", "-v", "help"]);

function parseServerArgs(argv) {
  let profileArg = null;
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === "--tools" && i + 1 < argv.length) {
      profileArg = argv[i + 1];
      i += 1;
    } else if (tok.startsWith("--tools=")) {
      profileArg = tok.slice("--tools=".length);
    }
  }
  return { profile: resolveToolProfile(profileArg) };
}

const rawArgs = process.argv.slice(2);
if (rawArgs.length > 0 && CLI_SUBCOMMANDS.has(rawArgs[0])) {
  const { runCli } = await import("./cli.mjs");
  const exitCode = await runCli(rawArgs);
  process.exit(exitCode);
}

const { profile: ACTIVE_PROFILE } = parseServerArgs(rawArgs);
const ACTIVE_TOOLS = getToolsForProfile(ACTIVE_PROFILE);
const ipc = new MohoIpcClient();

const GUIDE_TEXT = [
  "# Moho Studio MCP v3.1.0 Quick Guide",
  `- Active tool profile: \`${ACTIVE_PROFILE}\` (${ACTIVE_TOOLS.length} tools listed; set \`MOHO_STUDIO_TOOLS=full|core|rigging|animation|vector\` or \`--tools <profile>\` to adjust context size).`,
  "- Read `moho-studio://playbook` first for 16 Moho Pro 14.4 rigging, character performance, shading, animation, glTF, and Lua safety rules.",
  "- Start every live session with `moho_status` to confirm Moho Pro 14.4 connectivity.",
  "- Before animating any character rig, call `rig_getControls` to discover its Smart Bone Dials (with exact angle sweeps), IK Targets, Pin Bones, SwitchLayers, Vitruvian groups, and Regular Actions.",
  "- When building studio character controls (Blink, Mouth, Head Turn, Body Turn, Eyebrows), use `bone_createSmartDial` to create labeled, zero-strength, constrained side dials with 96-frame Smart Bone Actions in one call.",
  "- Use `moho_apiInspect` (includes tolua++ `.get`/`.set` properties) before writing custom `lua_execute` scripts.",
  "- Use `batch_execute` for multi-bone, multi-layer, or multi-keyframe edits (single Undo step + coalesced UI refresh).",
  "- Use `rig_audit` to lint rigs for non-zero control-bone strength, rigid-group traps, Smart Bone layer-order collisions, active-action leaks, unbound artwork, and dynamics pre-roll.",
  "- Use `switch_importLipSync` to import Papagayo `.dat` (`MohoSwitch1`), Rhubarb Lip Sync JSON (`mouthCues`), or explicit cues onto any SwitchLayer.",
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
      const negotiated = negotiateProtocolVersion(params && params.protocolVersion);
      sendResult(id, {
        protocolVersion: negotiated,
        capabilities: {
          tools: {},
          resources: {},
          prompts: {},
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
        tools: ACTIVE_TOOLS.map(({ name, description, inputSchema, annotations }) => ({
          name,
          description,
          inputSchema,
          annotations,
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
            name: "Moho Pro 14.4 Authoring Playbook",
            description: "16 Moho Pro 14.4 rigging, studio control panel, character performance, vector shading, animation, and glTF rules plus Lua engine invariants",
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

    if (method === "prompts/list") {
      sendResult(id, {
        prompts: PROMPTS.map(({ name, description, arguments: promptArgs }) => ({
          name,
          description,
          arguments: promptArgs,
        })),
      });
      return;
    }

    if (method === "prompts/get") {
      const promptName = params && params.name;
      const promptDef = PROMPT_BY_NAME.get(promptName);
      if (!promptDef) {
        sendError(id, -32602, `Unknown prompt: ${promptName}`);
        return;
      }
      const promptArgs = (params && params.arguments) || {};
      for (const argSpec of promptDef.arguments || []) {
        if (argSpec.required && (!promptArgs[argSpec.name] || String(promptArgs[argSpec.name]).trim() === "")) {
          sendError(id, -32602, `Missing required prompt argument '${argSpec.name}' for '${promptName}'`);
          return;
        }
      }
      sendResult(id, {
        description: promptDef.description,
        messages: promptDef.buildMessages(promptArgs),
      });
      return;
    }

    sendError(id, -32601, `Method not found: ${method}`);
  } catch (err) {
    sendError(id, -32603, err.message || String(err));
  }
}

let inFlight = 0;
let stdinClosed = false;
let draining = false;

function maybeDrainAndExit() {
  if (draining || !stdinClosed || inFlight > 0) return;
  draining = true;
  ipc.stopKeepAlive();
  process.stdout.end();
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
  inFlight += 1;
  handleMessage(parsed)
    .catch((err) => {
      process.stderr.write(`[moho-studio-mcp] Unhandled error: ${err.stack || err}\n`);
    })
    .finally(() => {
      inFlight -= 1;
      maybeDrainAndExit();
    });
});

function forceShutdown() {
  ipc.stopKeepAlive();
  process.exit(0);
}

rl.on("close", () => {
  stdinClosed = true;
  maybeDrainAndExit();
});
process.on("SIGINT", forceShutdown);
process.on("SIGTERM", forceShutdown);
