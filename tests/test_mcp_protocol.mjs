import assert from "node:assert/strict";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.resolve(__dirname, "../src/server.mjs");

async function run() {
  const proc = spawn(process.execPath, [serverPath], {
    stdio: ["pipe", "pipe", "pipe"],
  });

  const messages = [
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "test-client", version: "3.0.0" },
      },
    },
    { jsonrpc: "2.0", method: "notifications/initialized" },
    { jsonrpc: "2.0", id: 2, method: "ping", params: {} },
    { jsonrpc: "2.0", id: 3, method: "tools/list", params: {} },
    { jsonrpc: "2.0", id: 4, method: "resources/list", params: {} },
    { jsonrpc: "2.0", id: 5, method: "resources/read", params: { uri: "moho-studio://guide" } },
    { jsonrpc: "2.0", id: 6, method: "resources/read", params: { uri: "moho-studio://playbook" } },
  ];

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

  const lines = stdout.trim().split(/\r?\n/).map((l) => JSON.parse(l));
  assert.equal(lines.length, 6, `Expected 6 JSON-RPC responses, got ${lines.length}`);

  const init = lines[0];
  assert.equal(init.result.serverInfo.name, "moho-studio-mcp");
  assert.equal(init.result.serverInfo.version, "3.0.0");

  const ping = lines[1];
  assert.deepEqual(ping.result, {});

  const toolsResp = lines[2];
  assert.ok(Array.isArray(toolsResp.result.tools));
  assert.equal(toolsResp.result.tools.length, 78, `Expected 78 tools, got ${toolsResp.result.tools.length}`);
  const byName = new Map(toolsResp.result.tools.map((t) => [t.name, t]));
  const names = new Set(byName.keys());
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
    "fbf_manage",
    "particle_configure",
    "bone_create",
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

  // Phase 1 schema verification
  assert.ok(byName.get("layer_create").inputSchema.properties.type.enum.includes("patch"), "layer_create missing 'patch' type");
  assert.ok(byName.get("bone_create").inputSchema.properties.pinBone, "bone_create missing pinBone");
  assert.ok(byName.get("bone_create").inputSchema.properties.scale, "bone_create missing scale");
  assert.ok(byName.get("mesh_createShape").inputSchema.properties.lineWidthPx, "mesh_createShape missing lineWidthPx");
  assert.ok(byName.get("layer_setProperties").inputSchema.properties.blurPx, "layer_setProperties missing blurPx");
  for (const field of ["windStrengthPercent", "turbulentAmplitudePercent", "turbulentFrequencyPercent", "gravityStrengthPercent"]) {
    assert.ok(byName.get("bone_setWind").inputSchema.properties[field], `bone_setWind missing ${field}`);
  }
  const interpPropTargets = [
    ["layer_setProperties", byName.get("layer_setProperties").inputSchema.properties],
    ["bone_setTransform", byName.get("bone_setTransform").inputSchema.properties],
    ["bone_setWind", byName.get("bone_setWind").inputSchema.properties],
    ["camera_setKeyframe", byName.get("camera_setKeyframe").inputSchema.properties],
    ["mesh_editPoints", byName.get("mesh_editPoints").inputSchema.properties],
    ["mesh_editPoints.edits[]", byName.get("mesh_editPoints").inputSchema.properties.edits.items.properties],
    ["animation_setKeyframes.keyframes[]", byName.get("animation_setKeyframes").inputSchema.properties.keyframes.items.properties],
  ];
  for (const [label, props] of interpPropTargets) {
    for (const k of ["interpolation", "cycleMode", "cycleTargetFrame", "interval", "val1", "val2", "colorTag"]) {
      assert.ok(props[k], `${label} missing interpolation field '${k}'`);
    }
  }

  // Phase 2 schema verification
  assert.ok(byName.get("bone_create").inputSchema.properties.headRef, "bone_create missing headRef");
  assert.ok(byName.get("bone_create").inputSchema.properties.tailRef, "bone_create missing tailRef");
  for (const field of ["posControlScale", "maxIKStretching", "squashStretch", "arcSolver", "chainBoneIds"]) {
    assert.ok(byName.get("bone_setConstraints").inputSchema.properties[field], `bone_setConstraints missing ${field}`);
  }
  for (const field of ["angleWeight", "posWeight", "scaleWeight", "enableBoneDynamics"]) {
    assert.ok(byName.get("bone_setDynamics").inputSchema.properties[field], `bone_setDynamics missing ${field}`);
  }
  assert.ok(byName.get("layer_setMasking").inputSchema.properties.preset, "layer_setMasking missing preset");
  assert.ok(byName.get("layer_setMasking").inputSchema.properties.excludeStrokes, "layer_setMasking missing excludeStrokes");
  assert.ok(byName.get("layer_reparent").inputSchema.properties.inFrontOfLayerId, "layer_reparent missing inFrontOfLayerId");
  assert.ok(byName.get("document_setSettings").inputSchema.properties.dof, "document_setSettings missing dof");
  for (const field of ["preserveApparentSize", "timingOffset", "shownOnTimeline", "colorize", "outline", "shadow", "shading", "vectorNoise"]) {
    assert.ok(byName.get("layer_setProperties").inputSchema.properties[field], `layer_setProperties missing ${field}`);
  }

  // Phase 3 schema verification
  const createShapeSchema = byName.get("mesh_createShape").inputSchema;
  assert.ok(!createShapeSchema.required || !createShapeSchema.required.includes("points"), "mesh_createShape should not strictly require points");
  for (const field of ["pointIds", "primitive", "holes", "softEdgePx", "roundCaps", "style1", "style2"]) {
    assert.ok(createShapeSchema.properties[field], `mesh_createShape missing ${field}`);
  }
  const editShapeProps = byName.get("mesh_editShape").inputSchema.properties;
  for (const field of ["fillColor", "strokeColor", "softEdgePx", "gradient", "effectOffset", "style1", "style2", "brush", "raise", "delete", "interpolation"]) {
    assert.ok(editShapeProps[field], `mesh_editShape missing ${field}`);
  }
  const editPtProps = byName.get("mesh_editPoints").inputSchema.properties.edits.items.properties;
  for (const field of ["width", "opacity", "colorDrift", "colored", "color", "colorStrength", "inHandle", "outHandle", "resetWidth", "resetCurvature"]) {
    assert.ok(editPtProps[field], `mesh_editPoints.edits[] missing ${field}`);
  }
  const topoOps = byName.get("mesh_editTopology").inputSchema.properties.operation.enum;
  for (const op of ["split_segments", "insert_point", "weld_points", "connect_and_create", "hide_edge", "delete_points", "mirror_points", "merge_shapes", "triangulate", "stroke_exposure"]) {
    assert.ok(topoOps.includes(op), `mesh_editTopology missing operation ${op}`);
  }
  const warpProps = byName.get("mesh_createSmartWarp").inputSchema.properties;
  assert.ok(warpProps.mode.enum.includes("quad"), "mesh_createSmartWarp missing 'quad' mode");
  for (const field of ["compressible", "curverWidth", "appendToLayerId", "autoBindToTargetBone"]) {
    assert.ok(warpProps[field], `mesh_createSmartWarp missing ${field}`);
  }
  assert.ok(byName.get("mesh_liquidShapes").inputSchema.properties.comboMode.enum.includes("clip"), "mesh_liquidShapes missing 'clip' alias");
  const profProps = byName.get("mesh_setCurveProfile").inputSchema.properties;
  for (const field of ["profileLayerId", "profileRepeat", "profileOffset", "clear"]) {
    assert.ok(profProps[field], `mesh_setCurveProfile missing ${field}`);
  }
  const styleProps = byName.get("style_manage").inputSchema.properties;
  assert.ok(styleProps.operation.enum.includes("list_brushes"), "style_manage missing list_brushes");
  assert.ok(styleProps.operation.enum.includes("new_from_shape"), "style_manage missing new_from_shape");
  for (const field of ["brush", "smartBoilInterval", "styleSlot", "matchLineWidth"]) {
    assert.ok(styleProps[field], `style_manage missing ${field}`);
  }

  // Phase 4 schema verification
  const gltfProps = byName.get("document_exportGltf").inputSchema.properties;
  for (const field of ["format", "outputDir", "fileName", "scale", "gridDensity", "zOffset", "flipZOrder", "fbf", "fbfStep", "reRender", "comment", "copyright"]) {
    assert.ok(gltfProps[field], `document_exportGltf missing ${field}`);
  }
  const importProps = byName.get("document_import").inputSchema.properties;
  for (const field of ["scaleMode", "minifyLayers", "minifyGroups", "expandGroups", "recenter"]) {
    assert.ok(importProps[field], `document_import missing SVG bridge field ${field}`);
  }
  const lcOps = byName.get("layercomp_manage").inputSchema.properties.operation.enum;
  for (const op of ["rename", "show", "hide", "snapshot_visible", "expose_timeline"]) {
    assert.ok(lcOps.includes(op), `layercomp_manage missing operation ${op}`);
  }
  const physProps = byName.get("physics_configure").inputSchema.properties;
  for (const field of ["lifetime", "bake", "startFrame", "endFrame"]) {
    assert.ok(physProps[field], `physics_configure missing ${field}`);
  }
  const fbfOps = byName.get("fbf_manage").inputSchema.properties.operation.enum;
  for (const op of ["list_timeline", "add_blank_frame", "duplicate_frame", "clone_frame", "delete_frame", "push_frames"]) {
    assert.ok(fbfOps.includes(op), `fbf_manage missing operation ${op}`);
  }
  const sbProps = byName.get("action_createSmartBone").inputSchema.properties;
  for (const field of ["mode", "duration", "deltaAngleDeg", "mirrorFrame0ToEnd", "leaveActive"]) {
    assert.ok(sbProps[field], `action_createSmartBone missing ${field}`);
  }
  const animGetProps = byName.get("animation_getKeyframes").inputSchema.properties;
  for (const ch of ["gravity_strength", "gravity_direction", "wind_turbulent_amplitude", "switch", "vitruvian_active_bone", "point_pos", "point_curvature", "point_width", "shape_color", "combo_blend", "layer_order", "bone_flip_h", "bone_target", "follow_path", "camera_track", "translation_x"]) {
    assert.ok(animGetProps.channel.enum.includes(ch), `animation_getKeyframes missing channel ${ch}`);
  }
  assert.ok(animGetProps.dimension, "animation_getKeyframes missing dimension");
  assert.ok(animGetProps.splitDimensions, "animation_getKeyframes missing splitDimensions");
  const animSetKeyProps = byName.get("animation_setKeyframes").inputSchema.properties.keyframes.items.properties;
  for (const bf of ["bezierInAngle", "bezierInPercent", "bezierOutAngle", "bezierOutPercent"]) {
    assert.ok(animSetKeyProps[bf], `animation_setKeyframes missing Bezier prop ${bf}`);
  }

  const resList = lines[3];
  assert.equal(resList.result.resources.length, 2);
  const resUris = new Set(resList.result.resources.map((r) => r.uri));
  assert.ok(resUris.has("moho-studio://guide"), "Missing moho-studio://guide resource");
  assert.ok(resUris.has("moho-studio://playbook"), "Missing moho-studio://playbook resource");

  const resGuide = lines[4];
  assert.ok(resGuide.result.contents[0].text.includes("Moho Studio MCP v3.0.0 Quick Guide"));
  assert.ok(resGuide.result.contents[0].text.includes("moho-studio://playbook"));

  const resPlaybook = lines[5];
  const pbText = resPlaybook.result.contents[0].text;
  assert.ok(pbText.includes("Moho Pro 14.4 Authoring Playbook"));
  for (let i = 1; i <= 15; i += 1) {
    assert.ok(pbText.includes(`## ${i}. `), `Playbook missing rule ## ${i}.`);
  }

  console.log(`PASS test_mcp_protocol: ${toolsResp.result.tools.length} tools verified, handshake + 2 resources OK`);
}

run().catch((err) => {
  console.error("FAIL test_mcp_protocol:", err);
  process.exit(1);
});
