// Built-in MCP prompt templates for common Moho Pro 14.4 production workflows.

export const PROMPTS = [
  {
    name: "rig_character",
    description: "Build and audit a production character skeleton on Frame 0 with explicit bindings and zero-strength control bones.",
    arguments: [
      {
        name: "characterName",
        description: "Name of the character or BoneLayer to rig.",
        required: true,
      },
      {
        name: "style",
        description: "Rig style: vector, cutout, or hybrid (default: vector).",
        required: false,
      },
    ],
    buildMessages({ characterName = "Character", style = "vector" } = {}) {
      return [
        {
          role: "user",
          content: {
            type: "text",
            text: [
              `Rig the Moho Pro 14.4 character "${characterName}" (${style} workflow).`,
              "Follow these steps in order:",
              "1. Call `moho_status` and `layer_list`, and confirm the timeline is at Frame 0 and Mainline (`action_activate` with `actionName: ''`).",
              "2. Create or inspect the root BoneLayer and place artwork layers inside it.",
              "3. Build the spine, head, and left limbs using `bone_create` (prefer `headRef`/`tailRef` to snap joints to artwork) and batch multi-bone edits with `batch_execute`.",
              "4. Mirror left-side limbs with `bone_mirror` across the center X axis so constraints, dynamics, and IK targets stay symmetric.",
              "5. Set `strength: 0` via `bone_setProperties` on every Pin Bone, IK Target, and Smart Bone dial so control bones never deform artwork.",
              "6. Bind every artwork layer explicitly using `layer_bindToBone` (`boneId` for rigid parts, `flexiBoneIds` for limb subsets) or vector point binding (`mesh_editPoints` `parentBone`). Never rigid-bind a GroupLayer that holds independently bone-bound children.",
              "7. Run `rig_audit` on the BoneLayer and resolve all errors and warnings.",
              "8. Render a quick Frame 0 and posed check frame with `document_renderFrame` to verify deformation.",
            ].join("\n"),
          },
        },
      ];
    },
  },
  {
    name: "create_360_turnaround",
    description: "Author a smooth +/-360-degree Smart Bone head or body turnaround without angle wrap glitches or layer-order collisions.",
    arguments: [
      {
        name: "boneLayerName",
        description: "Target BoneLayer name (optional if already selected).",
        required: false,
      },
      {
        name: "dialBoneName",
        description: "Smart Bone dial name (default: HeadTurn).",
        required: false,
      },
      {
        name: "duration",
        description: "Action duration in frames (default: 96).",
        required: false,
      },
    ],
    buildMessages({ boneLayerName = "", dialBoneName = "HeadTurn", duration = "96" } = {}) {
      const targetNote = boneLayerName ? ` on BoneLayer "${boneLayerName}"` : "";
      return [
        {
          role: "user",
          content: {
            type: "text",
            text: [
              `Create a 360-degree Smart Bone turnaround driven by "${dialBoneName}"${targetNote} with duration ${duration} frames.`,
              "Follow these steps:",
              "1. Call `moho_status` and `bone_list` to verify the dial bone exists at Frame 0 with `strength: 0`.",
              `2. Call \`action_createSmartBone\` with \`boneName: "${dialBoneName}"\`, \`mode: "360"\`, \`duration: ${Number(duration) || 96}\`, \`addMidpointKey: true\`, \`mirrorFrame0ToEnd: true\`, and \`leaveActive: true\`.`,
              "3. Keyframe the 90-degree, 180-degree (back view), and 270-degree poses using `mesh_editPoints`, `layer_setProperties`, and `layer_setLayerOrder` (keep Animated Layer Order inside only one Smart Bone per Group to avoid collisions).",
              "4. Return to Mainline (`action_activate` with `actionName: ''`).",
              "5. Run `rig_audit` to verify there are no active-action leaks, non-zero dial strengths, or layer-order collisions.",
              "6. Scrub the dial on Mainline and render check frames with `document_renderFrame`.",
            ].join("\n"),
          },
        },
      ];
    },
  },
  {
    name: "painterly_vector_shading",
    description: "Style vector layers with Saved Styles, Moho 14 Brushes (Merged Alpha + Smart Line Boil), Point Colors, and masked shading.",
    arguments: [
      {
        name: "layerName",
        description: "Target VectorLayer or GroupLayer name (optional).",
        required: false,
      },
      {
        name: "styleTheme",
        description: "Visual direction, e.g. storybook watercolor, cel-shaded anime, charcoal ink.",
        required: false,
      },
    ],
    buildMessages({ layerName = "", styleTheme = "painterly ink and soft shading" } = {}) {
      const scope = layerName ? ` on "${layerName}"` : " in the active document";
      return [
        {
          role: "user",
          content: {
            type: "text",
            text: [
              `Apply a "${styleTheme}" look${scope} in Moho Pro 14.4.`,
              "Follow these steps:",
              "1. Inspect existing styles and brushes using `style_manage` (`operation: 'list'` and `operation: 'list_brushes'`).",
              "2. Create reusable Saved Styles (`style_manage` `create` or `new_from_shape`) so fill, outline, brush, and Smart Line Boil settings stay consistent across layers.",
              "3. Apply `brush` (`mergedAlpha: true`, subtle `jitter`/`spacing`/`hueDrift`/`valDrift`, and `smartBoilInterval`) plus `softEdgePx` or `gradient` via `mesh_editShape`.",
              "4. Add local lighting variation on vertices with `mesh_editPoints` (`colored: true`, `color`, `colorStrength`) and variable line weights (`width`).",
              "5. For interior shadow or texture layers, group them and run `layer_setMasking` with `preset: 'mask_inside_bottom'` and `expandByPixel: true`.",
              "6. Always verify final appearance with `document_renderFrame` (Moho's viewport preview does not show full Soft Edge, Point Colors, or Merged-Alpha brush rendering).",
            ].join("\n"),
          },
        },
      ];
    },
  },
  {
    name: "prepare_gltf_export",
    description: "Audit a Moho 14.4 scene for game-engine compatibility and run headless glTF 2.0 / GLB export.",
    arguments: [
      {
        name: "outputDir",
        description: "Destination directory for the .glb or .gltf export (optional if document is saved).",
        required: false,
      },
      {
        name: "format",
        description: "Output format: glb, gltf, or both (default: glb).",
        required: false,
      },
    ],
    buildMessages({ outputDir = "", format = "glb" } = {}) {
      const dirArg = outputDir ? ` to "${outputDir}"` : " beside the saved .moho file";
      return [
        {
          role: "user",
          content: {
            type: "text",
            text: [
              `Audit the open Moho Pro 14.4 scene and export it as ${format}${dirArg}.`,
              "Follow these steps:",
              "1. Run `moho_status` to check whether the document is saved and verify frame range and FPS.",
              "2. Run `rig_audit` to catch control-bone strength bugs, rigid-group traps, or active action leaks.",
              "3. Run `rig_auditGltf` to detect point-animated vectors lacking Smart Warp, active bone dynamics needing frame baking (`fbf: true`), and non-in-place Regular Actions.",
              "4. Fix reported warnings (or confirm whether `fbf: true` should be enabled for dynamics/point animation).",
              `5. Run \`document_exportGltf\` with \`format: "${format}"\`${outputDir ? ` and \`outputDir: "${outputDir}"\`` : ""}, and verify the exported file size and path.`,
            ].join("\n"),
          },
        },
      ];
    },
  },
  {
    name: "import_lipsync_animation",
    description: "Map and import Papagayo (.dat) or Rhubarb Lip Sync JSON cues onto a Moho mouth SwitchLayer.",
    arguments: [
      {
        name: "switchLayerName",
        description: "Name of the mouth SwitchLayer.",
        required: true,
      },
      {
        name: "sourcePath",
        description: "Path to a Papagayo .dat or Rhubarb .json file (optional if passing inline cues).",
        required: false,
      },
      {
        name: "format",
        description: "Input format: auto, papagayo, or rhubarb_json (default: auto).",
        required: false,
      },
    ],
    buildMessages({ switchLayerName = "Mouth", sourcePath = "", format = "auto" } = {}) {
      const srcLine = sourcePath
        ? `2. Call \`switch_importLipSync\` on "${switchLayerName}" with \`filePath: "${sourcePath}"\` and \`format: "${format}"\`.`
        : `2. Call \`switch_importLipSync\` on "${switchLayerName}" with \`format: "${format}"\` and the provided \`data\` or \`cues\`.`;
      return [
        {
          role: "user",
          content: {
            type: "text",
            text: [
              `Import lip-sync keyframes onto SwitchLayer "${switchLayerName}".`,
              "Follow these steps:",
              `1. Call \`switch_setActive\` on "${switchLayerName}" (read-only) to inspect existing mouth child layer names (for example Preston Blair set: AI, E, etc, FV, L, MBP, O, rest, U, WQ, or Rhubarb A-H/X).`,
              srcLine,
              "   - If the source uses Rhubarb letters (A-H, X) and the SwitchLayer uses Preston Blair names, pass `preset: 'rhubarb_to_preston_blair'` (or a custom `phonemeMap`) and `fallbackChild: 'rest'`.",
              "   - Pass `clearExisting: true` if replacing an older lip-sync pass (Frame 0 setup key is preserved automatically).",
              "3. Inspect `missingChildren` and `skippedCues` in the response; adjust `phonemeMap` if any phoneme did not match.",
              "4. Render 2-3 speech frames with `document_renderFrame` to visually verify mouth shapes.",
            ].join("\n"),
          },
        },
      ];
    },
  },
  {
    name: "animate_character_performance",
    description: "Inspect an existing Moho character's puppet controls first (rig_getControls) and animate blinks, mouth/speech, body turns, walk cycles, and arm gestures like a studio animator.",
    arguments: [
      {
        name: "performance",
        description: "Requested acting beat or action (e.g. 'walk forward, blink twice, wave right arm and open mouth').",
        required: true,
      },
      {
        name: "boneLayerName",
        description: "Target character BoneLayer name (optional if only one character is in the scene).",
        required: false,
      },
      {
        name: "durationFrames",
        description: "Shot length in frames (default: 72).",
        required: false,
      },
    ],
    buildMessages({ performance = "idle breathing, blink, and wave", boneLayerName = "", durationFrames = "72" } = {}) {
      const targetNote = boneLayerName ? ` on BoneLayer "${boneLayerName}"` : "";
      return [
        {
          role: "user",
          content: {
            type: "text",
            text: [
              `Animate the Moho Pro 14.4 character${targetNote} over ${durationFrames} frames: "${performance}".`,
              "Follow the Moho studio control-first workflow:",
              "1. Call `moho_status` and `rig_getControls` FIRST to discover every existing Smart Bone Dial (and its exact angle sweep range), IK Target, Pin Bone, SwitchLayer, Vitruvian Bone group, and Regular Action.",
              "2. Never drag raw vector points on Mainline when a Smart Bone Dial, SwitchLayer, or IK Target already controls that part.",
              "3. Plan and keyframe the performance in passes using `batch_execute` and `bone_setTransform` / `animation_setKeyframes`:",
              "   - Root, hips, and Foot IK Targets first (for walks: Contact -> Down -> Passing -> Up -> Contact every 12 frames, looped cleanly via `animation_createCycle` targeting Frame 2).",
              "   - Body and Head Smart Bone Dials (turn inside each dial's documented `startAngleDeg..endAngleDeg` sweep).",
              "   - Arms and hands in curved arcs with 2-4 frame shoulder -> forearm -> hand follow-through and `animation_tween` breakdowns / overshoot.",
              "   - Face acting: eye blinks (2f close, 1-2f hold, 3-4f ease-out open on the Blink dial), brow accents, and mouth/lip-sync via `Mouth` dial or `switch_importLipSync`.",
              "4. Render key storytelling frames (start, contact/peak, blink/mouth accent, end) via `document_renderFrame` to visually verify silhouettes and pose readability.",
            ].join("\n"),
          },
        },
      ];
    },
  },
  {
    name: "build_smart_bone_controls",
    description: "Build a side-mounted studio Smart Bone Dial panel (Blink, Mouth, Head Turn, Body Turn, Eyebrows) beside a character rig using bone_createSmartDial.",
    arguments: [
      {
        name: "boneLayerName",
        description: "Target character BoneLayer name (optional if already selected).",
        required: false,
      },
      {
        name: "dials",
        description: "Comma-separated list of dials to create (default: 'Blink, Mouth Open, Head Turn, Body Turn, Eyebrows').",
        required: false,
      },
    ],
    buildMessages({ boneLayerName = "", dials = "Blink, Mouth Open, Head Turn, Body Turn, Eyebrows" } = {}) {
      const targetNote = boneLayerName ? ` on BoneLayer "${boneLayerName}"` : "";
      return [
        {
          role: "user",
          content: {
            type: "text",
            text: [
              `Build a professional Moho Smart Bone Control Panel${targetNote} with dials: ${dials}.`,
              "Follow these steps:",
              "1. Confirm Frame 0 and Mainline (`moho_status`, `action_activate` with `actionName: ''`).",
              "2. Inspect existing controls (`rig_getControls`) and layer structure (`layer_list`) so you do not duplicate dials or collide Animated Layer Order across multiple Smart Bones.",
              "3. Create each dial beside the character with `bone_createSmartDial` (auto-places in a neat side column with `strength: 0`, `ignoredByIK: true`, `showLabel: true`, angle limit wedges, and 96-frame linear Smart Bone Actions):",
              "   - Use `bidirectional: false` (`deltaAngleDeg: 90`) for one-way dials such as `Blink` or `Mouth Open`.",
              "   - Use `bidirectional: true` (`minDeg: -90, maxDeg: 90`) for two-way dials such as `Head Turn`, `Body Turn`, or `Eyebrows`.",
              "4. Enter each Smart Bone Action (`action_activate`) to pose the eyes, eyelids, mouth shapes, or turned head/body layers at Frame 96 (and midpoint Frame 48 if needed), then return to Mainline (`actionName: ''`).",
              "5. Run `rig_audit` and `rig_getControls` to confirm every dial has zero strength, clean constraints, and zero warnings, then render test dial poses with `document_renderFrame`.",
            ].join("\n"),
          },
        },
      ];
    },
  },
];

export const PROMPT_BY_NAME = new Map(PROMPTS.map((p) => [p.name, p]));
