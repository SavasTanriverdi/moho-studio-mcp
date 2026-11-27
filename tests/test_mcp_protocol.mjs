import assert from "node:assert/strict";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.resolve(__dirname, "../src/server.mjs");

async function runSession(messages, { args = [], env = {} } = {}) {
  const proc = spawn(process.execPath, [serverPath, ...args], {
    stdio: ["pipe", "pipe", "pipe"],
    env: { ...process.env, ...env },
  });

  let stdout = "";
  let stderr = "";
  proc.stdout.on("data", (d) => { stdout += d.toString("utf8"); });
  proc.stderr.on("data", (d) => { stderr += d.toString("utf8"); });

  for (const m of messages) {
    proc.stdin.write(JSON.stringify(m) + "\n");
  }
  proc.stdin.end();

  const exitCode = await new Promise((resolve) => proc.on("close", resolve));
  assert.equal(exitCode, 0, `Server exited with ${exitCode}: ${stderr}`);
  return stdout.trim().split(/\r?\n/).map((l) => JSON.parse(l));
}

async function run() {
  const lines = await runSession([
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "test-client", version: "3.1.0" },
      },
    },
    { jsonrpc: "2.0", method: "notifications/initialized" },
    { jsonrpc: "2.0", id: 2, method: "ping", params: {} },
    { jsonrpc: "2.0", id: 3, method: "tools/list", params: {} },
    { jsonrpc: "2.0", id: 4, method: "resources/list", params: {} },
    { jsonrpc: "2.0", id: 5, method: "resources/read", params: { uri: "moho-studio://guide" } },
    { jsonrpc: "2.0", id: 6, method: "resources/read", params: { uri: "moho-studio://playbook" } },
    { jsonrpc: "2.0", id: 7, method: "prompts/list", params: {} },
    { jsonrpc: "2.0", id: 8, method: "prompts/get", params: { name: "rig_character", arguments: { characterName: "Hero", style: "vector" } } },
    { jsonrpc: "2.0", id: 9, method: "prompts/get", params: { name: "import_lipsync_animation", arguments: {} } },
    { jsonrpc: "2.0", id: 10, method: "resources/templates/list", params: {} },
  ]);

  assert.equal(lines.length, 10, `Expected 10 JSON-RPC responses, got ${lines.length}`);

  const init = lines[0];
  assert.equal(init.result.protocolVersion, "2025-03-26");
  assert.equal(init.result.serverInfo.name, "moho-studio-mcp");
  assert.equal(init.result.serverInfo.version, "3.1.0");
  assert.ok(init.result.capabilities.tools);
  assert.ok(init.result.capabilities.resources);
  assert.ok(init.result.capabilities.prompts);
  assert.equal(typeof init.result.instructions, "string");
  for (const needle of ["moho_status", "rig_getControls", "batch_execute", "rig_audit", "document_renderFrame"]) {
    assert.ok(init.result.instructions.includes(needle), `initialize.instructions missing '${needle}'`);
  }

  const ping = lines[1];
  assert.deepEqual(ping.result, {});

  const toolsResp = lines[2];
  assert.ok(Array.isArray(toolsResp.result.tools));
  assert.equal(toolsResp.result.tools.length, 82, `Expected 82 tools, got ${toolsResp.result.tools.length}`);
  const byName = new Map(toolsResp.result.tools.map((t) => [t.name, t]));
  const names = new Set(byName.keys());

  // Verify MCP annotations exist on every single tool
  for (const t of toolsResp.result.tools) {
    assert.ok(t.annotations && typeof t.annotations === "object", `Missing annotations on tool ${t.name}`);
    assert.equal(typeof t.annotations.title, "string", `Missing annotations.title on ${t.name}`);
    assert.equal(typeof t.annotations.readOnlyHint, "boolean", `Missing readOnlyHint on ${t.name}`);
    assert.equal(typeof t.annotations.destructiveHint, "boolean", `Missing destructiveHint on ${t.name}`);
    assert.equal(typeof t.annotations.idempotentHint, "boolean", `Missing idempotentHint on ${t.name}`);
    assert.equal(t.annotations.openWorldHint, false, `openWorldHint must be false on ${t.name}`);
  }
  assert.equal(byName.get("rig_audit").annotations.readOnlyHint, true);
  assert.equal(byName.get("rig_getControls").annotations.readOnlyHint, true);
  assert.equal(byName.get("rig_audit").annotations.destructiveHint, false);
  assert.equal(byName.get("bone_createSmartDial").annotations.destructiveHint, false);
  assert.equal(byName.get("layer_delete").annotations.destructiveHint, true);
  assert.equal(byName.get("switch_importLipSync").annotations.readOnlyHint, false);

  for (const required of [
    "moho_status",
    "moho_activatePoller",
    "moho_apiInspect",
    "lua_execute",
    "document_new",
    "document_open",
    "document_saveAs",
    "document_close",
    "document_undo",
    "document_import",
    "document_renderFrame",
    "document_captureWindow",
    "document_cliRender",
    "document_exportGltf",
    "rig_auditGltf",
    "rig_audit",
    "rig_getControls",
    "layercomp_list",
    "layercomp_manage",
    "layer_create",
    "layer_duplicate",
    "layer_bindToBone",
    "layer_setMasking",
    "layer_setLayerOrder",
    "layer_convertType",
    "layer_groupSelection",
    "layer_followPath",
    "layer_referenceManage",
    "layer_renderImage",
    "switch_setActive",
    "switch_importLipSync",
    "fbf_manage",
    "particle_configure",
    "bone_create",
    "bone_createSmartDial",
    "bone_setDynamics",
    "bone_mirror",
    "bone_freezePose",
    "bone_listGroups",
    "bone_manageGroup",
    "bone_setWind",
    "physics_configure",
    "animation_createCycle",
    "animation_retime",
    "animation_tween",
    "timeline_markers",
    "action_activate",
    "action_createSmartBone",
    "action_manage",
    "mesh_createShape",
    "mesh_editShape",
    "mesh_editPoints",
    "mesh_editTopology",
    "mesh_createSmartWarp",
    "mesh_setCurveProfile",
    "mesh_liquidShapes",
    "style_manage",
    "batch_execute",
  ]) {
    assert.ok(names.has(required), `Missing required tool: ${required}`);
  }

  // v3.1.0 new tool schema checks
  const lipProps = byName.get("switch_importLipSync").inputSchema.properties;
  for (const field of ["filePath", "data", "cues", "format", "fps", "frameOffset", "preset", "phonemeMap", "fallbackChild", "clearExisting", "dedupeAdjacent"]) {
    assert.ok(lipProps[field], `switch_importLipSync missing ${field}`);
  }
  assert.ok(lipProps.preset.enum.includes("rhubarb_to_preston_blair"));

  const auditProps = byName.get("rig_audit").inputSchema.properties;
  for (const field of ["layerId", "layerName", "checkUnboundArtwork", "checkDynamicsPreRoll", "strengthEpsilon"]) {
    assert.ok(auditProps[field], `rig_audit missing ${field}`);
  }

  const ctrlProps = byName.get("rig_getControls").inputSchema.properties;
  assert.ok(ctrlProps.frame && ctrlProps.layerName, "rig_getControls missing frame/layerName");
  const dialProps = byName.get("bone_createSmartDial").inputSchema.properties;
  for (const field of ["name", "bidirectional", "minDeg", "maxDeg", "deltaAngleDeg", "secondDeltaAngleDeg", "side", "leaveActive"]) {
    assert.ok(dialProps[field], `bone_createSmartDial missing ${field}`);
  }

  // TDQS 100% parameter description coverage check across ALL 80 tools
  for (const tool of toolsResp.result.tools) {
    const props = tool.inputSchema.properties || {};
    for (const [k, v] of Object.entries(props)) {
      assert.ok(v.description && v.description.length > 0, `${tool.name}.${k} missing description`);
    }
  }

  // Core layer, bone, warp, glTF, and animation channel schema assertions
  assert.equal(names.size, toolsResp.result.tools.length, "Duplicate tool names detected in tools/list");
  assert.ok(byName.get("layer_create").inputSchema.properties.type.enum.includes("patch"));
  assert.ok(byName.get("bone_create").inputSchema.properties.pinBone);
  assert.ok(byName.get("bone_create").inputSchema.properties.headRef);
  assert.ok(byName.get("mesh_createSmartWarp").inputSchema.properties.mode.enum.includes("quad"));
  assert.ok(byName.get("document_exportGltf").inputSchema.properties.fbf);
  assert.ok(byName.get("animation_getKeyframes").inputSchema.properties.channel.enum.includes("translation_x"));

  // Resources checks
  const resList = lines[3];
  assert.equal(resList.result.resources.length, 2);
  const resGuide = lines[4];
  assert.ok(resGuide.result.contents[0].text.includes("Moho Studio MCP v3.1.0 Quick Guide"));
  assert.ok(resGuide.result.contents[0].text.includes("rig_audit"));
  assert.ok(resGuide.result.contents[0].text.includes("switch_importLipSync"));

  const resPlaybook = lines[5];
  const pbText = resPlaybook.result.contents[0].text;
  assert.ok(pbText.includes("Moho Pro 14.4 Authoring Playbook"));
  for (let i = 1; i <= 16; i += 1) {
    assert.ok(pbText.includes(`## ${i}. `), `Playbook missing rule ## ${i}.`);
  }

  // Prompts checks
  const promptsList = lines[6];
  assert.equal(promptsList.result.prompts.length, 7);
  const promptNames = new Set(promptsList.result.prompts.map((p) => p.name));
  for (const pn of [
    "rig_character",
    "create_360_turnaround",
    "painterly_vector_shading",
    "prepare_gltf_export",
    "import_lipsync_animation",
    "animate_character_performance",
    "build_smart_bone_controls",
  ]) {
    assert.ok(promptNames.has(pn), `Missing prompt: ${pn}`);
  }
  const promptGetOk = lines[7];
  assert.equal(promptGetOk.result.messages.length, 1);
  assert.ok(promptGetOk.result.messages[0].content.text.includes("Hero"));
  assert.ok(promptGetOk.result.messages[0].content.text.includes("rig_audit"));
  const promptGetErr = lines[8];
  assert.ok(promptGetErr.error && promptGetErr.error.code === -32602, "Missing required prompt arg should return -32602");

  const resTemplates = lines[9];
  assert.deepEqual(resTemplates.result, { resourceTemplates: [] });

  // Legacy 2024-11-05 negotiation + core profile filtering check
  const coreLines = await runSession(
    [
      { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {} } },
      { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} },
    ],
    { env: { MOHO_STUDIO_TOOLS: "core" } }
  );
  assert.equal(coreLines[0].result.protocolVersion, "2024-11-05");
  assert.equal(coreLines[1].result.tools.length, 28, `Expected 28 core tools, got ${coreLines[1].result.tools.length}`);

  // CLI --tools flag override check
  const animLines = await runSession(
    [{ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }],
    { args: ["--tools", "animation"] }
  );
  assert.ok(animLines[0].result.tools.some((t) => t.name === "switch_importLipSync"));
  assert.ok(animLines[0].result.tools.some((t) => t.name === "rig_getControls"));
  assert.ok(animLines[0].result.tools.length < 82);

  console.log(`PASS test_mcp_protocol: ${toolsResp.result.tools.length} tools + annotations + 7 prompts + profiles + protocol negotiation OK`);
}

run().catch((err) => {
  console.error("FAIL test_mcp_protocol:", err);
  process.exit(1);
});
