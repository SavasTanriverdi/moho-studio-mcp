// Tool catalog index combining domain schema modules, MCP annotations, and tool profiles.

import { SYSTEM_TOOLS } from "./tools/system.mjs";
import { DOCUMENT_TOOLS } from "./tools/document.mjs";
import { LAYER_TOOLS } from "./tools/layers.mjs";
import { BONE_TOOLS } from "./tools/bones.mjs";
import { ANIMATION_TOOLS } from "./tools/animation.mjs";
import { MESH_TOOLS } from "./tools/mesh.mjs";
import { BATCH_TOOLS } from "./tools/batch.mjs";

export const TOOLS = [
  ...SYSTEM_TOOLS,
  ...DOCUMENT_TOOLS,
  ...LAYER_TOOLS,
  ...BONE_TOOLS,
  ...ANIMATION_TOOLS,
  ...MESH_TOOLS,
  ...BATCH_TOOLS,
];

// MCP 2025-03-26 tool annotations (readOnlyHint, destructiveHint, idempotentHint, openWorldHint).
const READ_ONLY_TOOLS = new Set([
  "moho_status",
  "moho_apiInspect",
  "document_getInfo",
  "rig_auditGltf",
  "rig_audit",
  "rig_getControls",
  "layercomp_list",
  "layer_list",
  "layer_getProperties",
  "bone_list",
  "bone_listGroups",
  "animation_getKeyframes",
  "action_list",
  "camera_get",
  "mesh_getData",
]);

const DESTRUCTIVE_TOOLS = new Set([
  "lua_execute",
  "document_close",
  "document_undo",
  "layercomp_manage",
  "layer_delete",
  "layer_convertType",
  "layer_referenceManage",
  "fbf_manage",
  "bone_delete",
  "bone_manageGroup",
  "animation_deleteKeyframe",
  "animation_retime",
  "timeline_markers",
  "action_manage",
  "mesh_editShape",
  "mesh_editTopology",
  "mesh_liquidShapes",
  "style_manage",
  "batch_execute",
]);

const IDEMPOTENT_TOOLS = new Set([
  ...READ_ONLY_TOOLS,
  "moho_activatePoller",
  "document_save",
  "document_saveAs",
  "document_setSettings",
  "document_setFrame",
  "document_renderFrame",
  "document_renderRange",
  "document_captureWindow",
  "document_cliRender",
  "document_exportGltf",
  "layer_select",
  "layer_setProperties",
  "layer_bindToBone",
  "layer_setWarpLayer",
  "layer_setMasking",
  "layer_setLayerOrder",
  "layer_followPath",
  "layer_renderImage",
  "switch_setActive",
  "particle_configure",
  "bone_setTransform",
  "bone_setProperties",
  "bone_setConstraints",
  "bone_setDynamics",
  "bone_freezePose",
  "bone_setWind",
  "physics_configure",
  "animation_setKeyframes",
  "animation_createCycle",
  "animation_tween",
  "action_activate",
  "camera_setKeyframe",
  "mesh_editPoints",
  "mesh_setCurveProfile",
]);

function formatToolTitle(name) {
  return name
    .split("_")
    .map((part) => part.replace(/([a-z0-9])([A-Z])/g, "$1 $2"))
    .join(" ")
    .replace(/\b\w/g, (ch) => ch.toUpperCase())
    .replace(/\bGltf\b/g, "glTF")
    .replace(/\bFbf\b/g, "FBF")
    .replace(/\bCli\b/g, "CLI")
    .replace(/\bApi\b/g, "API");
}

for (const tool of TOOLS) {
  const isReadOnly = READ_ONLY_TOOLS.has(tool.name);
  tool.annotations = {
    title: formatToolTitle(tool.name),
    readOnlyHint: isReadOnly,
    destructiveHint: isReadOnly ? false : DESTRUCTIVE_TOOLS.has(tool.name),
    idempotentHint: IDEMPOTENT_TOOLS.has(tool.name),
    openWorldHint: false,
  };
}

// Tool profiles selectable via MOHO_STUDIO_TOOLS or --tools.
const SHARED_BASE_TOOLS = [
  "moho_status",
  "moho_activatePoller",
  "moho_apiInspect",
  "lua_execute",
  "document_getInfo",
  "document_new",
  "document_open",
  "document_save",
  "document_saveAs",
  "document_close",
  "document_undo",
  "document_setFrame",
  "document_renderFrame",
  "document_captureWindow",
  "batch_execute",
];

export const TOOL_PROFILES_MAP = {
  core: new Set([
    "moho_status",
    "moho_activatePoller",
    "moho_apiInspect",
    "lua_execute",
    "document_getInfo",
    "document_new",
    "document_open",
    "document_save",
    "document_setFrame",
    "document_renderFrame",
    "document_captureWindow",
    "layer_list",
    "layer_getProperties",
    "layer_create",
    "layer_setProperties",
    "layer_bindToBone",
    "layer_setMasking",
    "bone_list",
    "bone_create",
    "bone_createSmartDial",
    "rig_audit",
    "rig_getControls",
    "animation_getKeyframes",
    "animation_setKeyframes",
    "action_activate",
    "mesh_getData",
    "mesh_createShape",
    "batch_execute",
  ]),
  rigging: new Set([
    ...SHARED_BASE_TOOLS,
    "document_import",
    "document_exportGltf",
    "rig_audit",
    "rig_getControls",
    "rig_auditGltf",
    "layer_list",
    "layer_getProperties",
    "layer_create",
    "layer_delete",
    "layer_duplicate",
    "layer_reparent",
    "layer_select",
    "layer_setProperties",
    "layer_bindToBone",
    "layer_setWarpLayer",
    "layer_setMasking",
    "layer_setLayerOrder",
    "layer_convertType",
    "layer_groupSelection",
    "layer_referenceManage",
    "bone_list",
    "bone_create",
    "bone_createSmartDial",
    "bone_delete",
    "bone_setTransform",
    "bone_setProperties",
    "bone_setConstraints",
    "bone_setDynamics",
    "bone_mirror",
    "bone_freezePose",
    "bone_listGroups",
    "bone_manageGroup",
    "bone_setWind",
    "action_list",
    "action_activate",
    "action_createSmartBone",
    "action_manage",
    "mesh_getData",
    "mesh_editPoints",
    "mesh_createSmartWarp",
  ]),
  animation: new Set([
    ...SHARED_BASE_TOOLS,
    "document_setSettings",
    "document_renderRange",
    "document_cliRender",
    "document_exportGltf",
    "rig_audit",
    "rig_getControls",
    "rig_auditGltf",
    "layercomp_list",
    "layercomp_manage",
    "layer_list",
    "layer_getProperties",
    "layer_select",
    "layer_setProperties",
    "layer_setLayerOrder",
    "layer_followPath",
    "layer_renderImage",
    "switch_setActive",
    "switch_importLipSync",
    "fbf_manage",
    "particle_configure",
    "bone_list",
    "bone_setTransform",
    "bone_setDynamics",
    "bone_freezePose",
    "bone_listGroups",
    "bone_manageGroup",
    "bone_setWind",
    "physics_configure",
    "animation_getKeyframes",
    "animation_setKeyframes",
    "animation_deleteKeyframe",
    "animation_createCycle",
    "animation_retime",
    "animation_tween",
    "timeline_markers",
    "action_list",
    "action_activate",
    "action_createSmartBone",
    "action_manage",
    "camera_get",
    "camera_setKeyframe",
  ]),
  vector: new Set([
    ...SHARED_BASE_TOOLS,
    "document_setSettings",
    "document_import",
    "layer_list",
    "layer_getProperties",
    "layer_create",
    "layer_delete",
    "layer_duplicate",
    "layer_reparent",
    "layer_select",
    "layer_setProperties",
    "layer_setWarpLayer",
    "layer_setMasking",
    "layer_groupSelection",
    "layer_renderImage",
    "mesh_getData",
    "mesh_createShape",
    "mesh_editShape",
    "mesh_editPoints",
    "mesh_editTopology",
    "mesh_createSmartWarp",
    "mesh_setCurveProfile",
    "mesh_liquidShapes",
    "style_manage",
  ]),
};

export function getToolsForProfile(profile = "full") {
  const key = String(profile || "full").trim().toLowerCase();
  if (key === "full" || !TOOL_PROFILES_MAP[key]) {
    return TOOLS;
  }
  const allow = TOOL_PROFILES_MAP[key];
  return TOOLS.filter((t) => allow.has(t.name));
}

export const TOOL_BY_NAME = new Map(TOOLS.map((t) => [t.name, t]));
