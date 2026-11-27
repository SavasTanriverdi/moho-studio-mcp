// Document lifecycle, rendering, glTF export, rig audit/controls, and Layer Comp tools.

import { LAYER_SELECTOR_PROPS, RGBA_SCHEMA } from "./shared.mjs";

export const DOCUMENT_TOOLS = [
  {
    name: "document_getInfo",
    rpcMethod: "document.getInfo",
    description: "Get open document metadata (name, path, dimensions, FPS, frame range, current frame, layer counts, Layer Comp count, active doc action, background color).",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "document_new",
    rpcMethod: "document.new",
    description: "Create a brand-new Moho document and optionally configure dimensions, FPS, frame range, and background color.",
    inputSchema: {
      type: "object",
      properties: {
        width: { type: "number", description: "Canvas width in pixels (default: 1920)" },
        height: { type: "number", description: "Canvas height in pixels (default: 1080)" },
        fps: { type: "number", description: "Frames per second (default: 24)" },
        startFrame: { type: "number", description: "Timeline start frame (default: 1)" },
        endFrame: { type: "number", description: "Timeline end frame (default: 240)" },
        backColor: RGBA_SCHEMA,
      },
    },
  },
  {
    name: "document_open",
    rpcMethod: "document.open",
    description: "Open an existing .moho project file from disk live inside Moho.",
    inputSchema: {
      type: "object",
      required: ["path"],
      properties: {
        path: { type: "string", description: "Absolute file path to the .moho project" },
      },
    },
  },
  {
    name: "document_save",
    rpcMethod: "document.save",
    description: "Save the currently open Moho document in place.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "document_saveAs",
    rpcMethod: "document.saveAs",
    description: "Save the currently open Moho document to a specific file path.",
    inputSchema: {
      type: "object",
      required: ["path"],
      properties: {
        path: { type: "string", description: "Destination .moho file path" },
      },
    },
  },
  {
    name: "document_close",
    rpcMethod: "document.close",
    description: "Close the currently active Moho document tab cleanly (auto-saves if it has a path to prevent blocking Save prompts).",
    inputSchema: {
      type: "object",
      properties: {
        saveFirst: { type: "boolean", description: "Save before closing to avoid blocking Save dialogs (default: true)" },
        savePath: { type: "string", description: "Optional path to FileSaveAs before closing an untitled document" },
        force: { type: "boolean", description: "Allow closing an untitled document without saving (default: false)" },
      },
    },
  },
  {
    name: "document_undo",
    rpcMethod: "document.undo",
    description: "Undo or Redo one or more steps in the open Moho document.",
    inputSchema: {
      type: "object",
      properties: {
        mode: { type: "string", enum: ["undo", "redo"], description: "Default: 'undo'" },
        steps: { type: "number", description: "Number of steps (1..50, default: 1)" },
      },
    },
  },
  {
    name: "document_setSettings",
    rpcMethod: "document.setSettings",
    description: "Modify open document dimensions, FPS, start/end frames, background color (LM.rgb_color via verified SetBackCol), or Depth of Field.",
    inputSchema: {
      type: "object",
      properties: {
        width: { type: "number", description: "Canvas width in pixels" },
        height: { type: "number", description: "Canvas height in pixels" },
        fps: { type: "number", description: "Document frame rate (FPS)" },
        startFrame: { type: "number", description: "Playback/render start frame" },
        endFrame: { type: "number", description: "Playback/render end frame" },
        backColor: RGBA_SCHEMA,
        dof: {
          type: "object",
          description: "Guarded Depth of Field settings if exposed by active Moho version",
          properties: {
            enabled: { type: "boolean", description: "Enable project Depth of Field" },
            focusDistance: { type: "number", description: "Camera focus plane distance" },
            focusRange: { type: "number", description: "In-focus depth range" },
            maxBlur: { type: "number", description: "Raw maximum blur radius" },
            maxBlurPx: { type: "number", description: "Maximum blur radius in pixels" },
            applyToProjectDefaults: { type: "boolean", description: "Apply DOF settings to MOHO.MohoGlobals project defaults" },
          },
        },
      },
    },
  },
  {
    name: "document_import",
    rpcMethod: "document.import",
    description: "Import a PNG/JPG/WebP image directly as a live ImageLayer, import SVG headlessly through Moho 14.4 SS_SVGImport (with scaling/consolidation controls), or import PSD/Moho files via FileImport.",
    inputSchema: {
      type: "object",
      required: ["path"],
      properties: {
        path: { type: "string", description: "Absolute file path to import" },
        asImageLayer: { type: "boolean", description: "Create an ImageLayer and call SetSourceImage (default true for raster images)" },
        name: { type: "string", description: "Optional layer name for imported ImageLayer" },
        parentLayerId: { type: "number", description: "Optional parent Group/Bone layer ID" },
        parentLayerName: { type: "string", description: "Optional parent Group/Bone layer name" },
        mode: { type: "number", description: "Moho FileImport mode (default 0)" },
        scaleMode: {
          type: "string",
          enum: ["fit_50", "fit_100", "fit_200", "asset_50", "asset_100", "asset_200", "none"],
          description: "For .svg via SS_SVGImport: canvas-fit or asset-relative scaling preset",
        },
        minify: { type: "boolean", description: "For .svg via SS_SVGImport: enable layer consolidation (default: true)" },
        minifyLayers: { type: "boolean", description: "For .svg via SS_SVGImport: combine adjacent vector layers" },
        minifyGroups: { type: "boolean", description: "For .svg via SS_SVGImport: ungroup single-child groups" },
        minifyLayersUnnamed: { type: "boolean", description: "For .svg via SS_SVGImport: consolidate only unnamed layers" },
        expandGroups: { type: "boolean", description: "For .svg via SS_SVGImport: expand imported group hierarchy" },
        recenter: { type: "boolean", description: "For .svg via SS_SVGImport: recenter artwork in canvas" },
        useNativeSvgImport: { type: "boolean", description: "Force Moho's legacy FileImport instead of SS_SVGImport for .svg" },
        requireSvgBridge: { type: "boolean", description: "Return an error instead of falling back to FileImport if SS_SVGImport fails" },
      },
    },
  },
  {
    name: "document_setFrame",
    rpcMethod: "document.setFrame",
    description: "Move Moho's timeline to a specific frame number.",
    inputSchema: {
      type: "object",
      required: ["frame"],
      properties: {
        frame: { type: "number", description: "Target frame number (0 for setup frame, >= 1 for animation)" },
      },
    },
  },
  {
    name: "document_renderFrame",
    rpcMethod: "document.renderFrame",
    timeoutKind: "render",
    returnsImage: true,
    description: "Render a specific frame live via Moho's FileRender engine and return the PNG.",
    inputSchema: {
      type: "object",
      properties: {
        frame: { type: "number", description: "Frame number to render (defaults to current frame)" },
        outputPath: { type: "string", description: "Optional PNG output path (defaults to temp folder)" },
        restoreFrame: { type: "boolean", description: "Restore timeline to prior frame after rendering (default: true)" },
        returnImage: { type: "boolean", description: "Include base64 PNG image content in MCP response (default: true)" },
      },
    },
  },
  {
    name: "document_renderRange",
    rpcMethod: "document.renderRange",
    timeoutKind: "renderRange",
    description: "Render a PNG frame sequence across a frame range live from the open Moho document (auto-creates outputDir).",
    inputSchema: {
      type: "object",
      required: ["outputDir"],
      properties: {
        outputDir: { type: "string", description: "Directory where PNG frames will be written" },
        startFrame: { type: "number", description: "First frame to render (defaults to document startFrame)" },
        endFrame: { type: "number", description: "Last frame to render (defaults to document endFrame)" },
        step: { type: "number", description: "Frame stride (default: 1)" },
        prefix: { type: "string", description: "Filename prefix (default: 'frame_')" },
      },
    },
  },
  {
    name: "document_captureWindow",
    rpcMethod: null,
    hostHandler: "captureWindow",
    returnsImage: true,
    description: "Capture the primary visible Moho Pro 14 application window (viewport, timeline, layers, toolbar) as PNG (Win32 PrintWindow on Windows, screencapture on macOS).",
    inputSchema: {
      type: "object",
      properties: {
        outputPath: { type: "string", description: "Optional PNG path to save the screenshot" },
      },
    },
  },
  {
    name: "document_cliRender",
    rpcMethod: null,
    hostHandler: "cliRender",
    returnsImage: true,
    defaultReturnImage: false,
    description: "Run Moho Pro 14.4's multi-threaded, GPU-accelerated headless CLI renderer (`Moho -r`) on any saved `.moho` file to export PNG sequences, MP4, MOV, AnimatedGIF, PSD, or SVG with optional Layer Comp filtering without blocking the Moho GUI.",
    inputSchema: {
      type: "object",
      required: ["projectPath"],
      properties: {
        projectPath: { type: "string", description: "Absolute path to saved .moho project file" },
        format: { type: "string", description: "Output format (PNG, MP4, MOV, AnimatedGIF, JPEG, BMP, TGA, PSD, SVG; default: PNG)" },
        outputDir: { type: "string", description: "Output folder (-outfolder); auto-created if missing" },
        outputFile: { type: "string", description: "Explicit output file path (-o) instead of outputDir" },
        startFrame: { type: "number", description: "First frame to render (-start)" },
        endFrame: { type: "number", description: "Last frame to render (-end)" },
        layerComp: { type: "string", description: "Render only a specific Layer Comp by name (-layercomp)" },
        createFoldersForLayerComps: { type: "boolean", description: "Create separate subfolders per Layer Comp" },
        addLayerCompSuffix: { type: "boolean", description: "Append Layer Comp name to output filenames" },
        halfSize: { type: "boolean", description: "Render at 50% width and height" },
        halfFps: { type: "boolean", description: "Render at half frame rate" },
        antiAliasing: { type: "boolean", description: "Enable anti-aliasing (default: true)" },
        shapeEffects: { type: "boolean", description: "Render shape effects like Soft Edge and Gradients (default: true)" },
        layerEffects: { type: "boolean", description: "Render layer effects like shadows and blur (default: true)" },
        extraSmooth: { type: "boolean", description: "Enable extra-smooth image sampling (default: true)" },
        premultiply: { type: "boolean", description: "Premultiply alpha channel (default: true)" },
        multithread: { type: "boolean", description: "Enable multi-threaded rendering" },
        returnImage: { type: "boolean", description: "If true and PNG was produced, include first PNG frame in MCP response (default: false)" },
        timeoutMs: { type: "number", description: "Render timeout in ms (default: 180000)" },
      },
    },
  },
  {
    name: "document_exportGltf",
    rpcMethod: "document.exportGltf",
    timeoutKind: "renderRange",
    description: "Headless Moho Pro 14.4 glTF 2.0 / GLB export wrapping Tool/ss_gltf_export.lua (bypasses SS_glTFExportDialog:DoModal safely). Run rig_auditGltf first to check for animated vectors without Warp Layers or non-in-place Actions.",
    inputSchema: {
      type: "object",
      properties: {
        format: { type: "string", enum: ["glb", "gltf", "both"], description: "Output container format (default: 'glb')" },
        outputDir: { type: "string", description: "Destination folder (required if document is unsaved; auto-created if missing)" },
        fileName: { type: "string", description: "Output base filename without extension (defaults to document name)" },
        scale: { type: "number", description: "Texture scaling factor 0.1..10.0 (default: 1.0 = 100%)" },
        gridDensity: { type: "number", description: "Mesh polygon resolution 1..100 (default: 20)" },
        zOffset: { type: "number", description: "Z-offset factor between stacked layers 0.1..100 (default: 1)" },
        flipZOrder: { type: "boolean", description: "Invert layer Z stacking order (default: false)" },
        fbf: { type: "boolean", description: "Bake every frame into glTF keyframes (preserves dynamics/Smart Bones; default: false)" },
        fbfStep: { type: "number", description: "Keyframe interval step when fbf=true (1..999, default: 1)" },
        reRender: { type: "string", enum: ["none", "all", "selected", "once"], description: "Re-render layer textures mode (default: 'none')" },
        comment: { type: "string", description: "Optional glTF asset metadata comment" },
        copyright: { type: "string", description: "Optional glTF asset copyright notice" },
      },
    },
  },
  {
    name: "rig_auditGltf",
    rpcMethod: "rig.auditGltf",
    description: "Read-only pre-flight audit of the open Moho document for glTF 2.0 export readiness: detects animated vector layers missing Warp Layers, active bone dynamics needing fbf baking, non-in-place Actions, unsaved document state, and gltf_* layer userTags.",
    inputSchema: {
      type: "object",
      properties: {
        inPlaceTolerance: { type: "number", description: "Max allowed root translation drift in Regular Actions before flagging warning (default: 0.15)" },
      },
    },
  },
  {
    name: "rig_audit",
    rpcMethod: "rig.audit",
    description: "Read-only Moho Pro 14.4 Rig Health Linter: checks for non-zero strength on Pin Bones / IK Targets / Smart Bone dials, rigid-bound GroupLayers trapping bone-bound children, Animated Layer Order collisions across multiple Smart Bone Actions, BoneLayers stuck in an active Action, unbound artwork under BoneLayers, and missing pre-roll for active Bone Dynamics or ParticleLayers.",
    inputSchema: {
      type: "object",
      properties: {
        ...LAYER_SELECTOR_PROPS,
        checkUnboundArtwork: { type: "boolean", description: "Flag Vector/Image child layers under a BoneLayer without explicit rigid, flexi-subset, or point binding (default: true)" },
        checkDynamicsPreRoll: { type: "boolean", description: "Flag active Bone Dynamics or ParticleLayers when document startFrame <= 1 (default: true)" },
        strengthEpsilon: { type: "number", description: "Threshold above which control-bone strength is reported as an error (default: 0.001)" },
      },
    },
  },
  {
    name: "rig_getControls",
    rpcMethod: "rig.getControls",
    description: "Read-only Puppet Control Surface inspector for any Moho character rig: call this BEFORE animating an existing character to discover all Smart Bone Dials (with exact angle sweeps, limits, and inferred roles like blink/mouth/body_turn), Foot/Hand IK Targets, Pin Bones, SwitchLayer controls, Vitruvian Bone groups, and Regular Actions in one call.",
    inputSchema: {
      type: "object",
      properties: {
        ...LAYER_SELECTOR_PROPS,
        frame: { type: "number", description: "Frame at which to sample current dial angles, IK positions, and active switch children (default: current frame)" },
      },
    },
  },
  {
    name: "layercomp_list",
    rpcMethod: "layercomp.list",
    description: "List all Layer Comps in the open document along with their member layers.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "layercomp_manage",
    rpcMethod: "layercomp.manage",
    description: "Create, update layer membership, apply, rename, additively show/hide, snapshot visible layers, expose on timeline, or delete Layer Comps.",
    inputSchema: {
      type: "object",
      required: ["operation"],
      properties: {
        operation: {
          type: "string",
          enum: ["create", "set_layers", "apply", "rename", "show", "hide", "snapshot_visible", "expose_timeline", "delete"],
          description: "Layer Comp operation to execute",
        },
        name: { type: "string", description: "Layer Comp name (target for all operations, or new name for create/snapshot_visible)" },
        newName: { type: "string", description: "New Layer Comp name (required for rename)" },
        index: { type: "number", description: "Zero-based Layer Comp index (alternative selector to name)" },
        layerIds: { type: "array", items: { type: "number" }, description: "Layer IDs to include (for create/set_layers)" },
        layerNames: { type: "array", items: { type: "string" }, description: "Layer names to include (for create/set_layers)" },
        includeChildren: { type: "boolean", description: "Recursively include descendant layers of specified Group/Bone/Switch layers (default: true)" },
        clearFirst: { type: "boolean", description: "Clear prior layers before adding (for set_layers, default: true)" },
        frame: { type: "number", description: "Frame for apply/show/hide/snapshot_visible operations" },
        shown: { type: "boolean", description: "For expose_timeline: show (true) or hide (false) comp layers on timeline (default: true)" },
        exclusive: { type: "boolean", description: "For expose_timeline: hide non-comp layers from timeline (default: false)" },
      },
    },
  },
];
