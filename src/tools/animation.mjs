// Keyframe, cycle, retiming, tween, marker, Action, Smart Bone, and camera tools.

import { LAYER_SELECTOR_PROPS, BONE_SELECTOR_PROPS, INTERP_ENUM, INTERP_PROPS, ANIM_CHANNEL_SELECTOR_PROPS } from "./shared.mjs";

export const ANIMATION_TOOLS = [
  {
    name: "animation_getKeyframes",
    rpcMethod: "animation.getKeyframes",
    description: "Read all keyframes, interpolation, Bezier handles, color tags, and Separate Dimensions from layer, bone, wind/gravity, Vitruvian, switch, vector point/shape, layer order, follow-path, or camera channels.",
    inputSchema: {
      type: "object",
      required: ["channel"],
      properties: {
        ...ANIM_CHANNEL_SELECTOR_PROPS,
      },
    },
  },
  {
    name: "animation_setKeyframes",
    rpcMethod: "animation.setKeyframes",
    description: "Batch-write multiple keyframes with Smooth/Linear/Ease/Step/Bezier (with handles)/Cycle/Bounce/Elastic/Stagger/Hold/ColorTag interpolation onto any supported Moho 14.4 animation channel (including Separate Dimensions).",
    inputSchema: {
      type: "object",
      required: ["channel", "keyframes"],
      properties: {
        ...ANIM_CHANNEL_SELECTOR_PROPS,
        ...INTERP_PROPS,
        keyframes: {
          type: "array",
          description: "Array of { frame, value, ...interp } keyframes to write onto the channel",
          items: {
            type: "object",
            required: ["frame", "value"],
            properties: {
              frame: { type: "number", description: "Target frame number" },
              value: { description: "Channel-typed value (number, boolean, string, {x,y}, {x,y,z}, or RGBA)" },
              ...INTERP_PROPS,
            },
          },
        },
      },
    },
  },
  {
    name: "animation_deleteKeyframe",
    rpcMethod: "animation.deleteKeyframe",
    description: "Delete a single keyframe (frame > 0) from any supported Moho 14.4 animation channel.",
    inputSchema: {
      type: "object",
      required: ["channel", "frame"],
      properties: {
        ...ANIM_CHANNEL_SELECTOR_PROPS,
        frame: { type: "number", description: "Keyframe number to delete (must be > 0)" },
      },
    },
  },
  {
    name: "animation_createCycle",
    rpcMethod: "animation.createCycle",
    description: "Build a loop-ready multi-channel animation cycle across [startFrame, endFrame]: ensures boundary keys at start/end, copies startFrame to endFrame when needed, and sets Cycle interpolation targeting startFrame + 1 (Frame 2 when starting at Frame 1) to avoid the double-frame stutter.",
    inputSchema: {
      type: "object",
      required: ["endFrame"],
      properties: {
        ...ANIM_CHANNEL_SELECTOR_PROPS,
        channels: {
          type: "array",
          description: "Optional list of channel names or channel selector objects to cycle together",
          items: {},
        },
        targets: {
          type: "array",
          description: "Optional explicit list of { layerName/Id, channel, boneName/Id, dimension, ... } targets",
          items: { type: "object", properties: { ...ANIM_CHANNEL_SELECTOR_PROPS } },
        },
        startFrame: { type: "number", description: "Cycle start frame (default: 1)" },
        endFrame: { type: "number", description: "Cycle end frame where Cycle interpolation is applied" },
        cycleMode: { type: "string", enum: ["relative", "absolute"], description: "Default: 'relative'" },
        cycleTargetFrame: { type: "number", description: "Loop target frame (default: startFrame + 1)" },
        additiveCycle: { type: "boolean", description: "Accumulate cycle offsets across repetitions (additive cycle)" },
        ensureStartKey: { type: "boolean", description: "Key startFrame if no key exists yet (default: true)" },
        copyStartToEnd: { type: "boolean", description: "Copy startFrame value to endFrame if endFrame has no key (default: true)" },
        forceCopyStartToEnd: { type: "boolean", description: "Always overwrite endFrame value with startFrame value (default: false)" },
        interpolationAtStart: { type: "string", enum: INTERP_ENUM, description: "Optional interpolation mode for startFrame (e.g. 'linear')" },
        interval: { type: "number", description: "Step interval in frames for the cycle keyframe (1=ones, 2=twos)" },
        colorTag: { type: "number", description: "Keyframe color tag index on the cycle keyframe" },
      },
    },
  },
  {
    name: "animation_retime",
    rpcMethod: "animation.retime",
    description: "Scoped keyframe retiming across explicit targets/channels (never accidentally shifts untouched scene layers): push_frames, scale_range (Alt+Drag), relative_offset, and clear_range (always protects frame 0).",
    inputSchema: {
      type: "object",
      required: ["operation"],
      properties: {
        ...ANIM_CHANNEL_SELECTOR_PROPS,
        operation: { type: "string", enum: ["push_frames", "scale_range", "relative_offset", "clear_range"], description: "Retiming operation to apply across selected channels" },
        channels: { type: "array", items: {}, description: "Optional list of channel names on the selected layer/bone to retime together" },
        targets: {
          type: "array",
          description: "Explicit list of channel targets to retime",
          items: { type: "object", properties: { ...ANIM_CHANNEL_SELECTOR_PROPS } },
        },
        fromFrame: { type: "number", description: "Start frame for push_frames (>= 1)" },
        toFrame: { type: "number", description: "Optional inclusive end frame for push_frames" },
        delta: { type: "number", description: "Frame shift delta for push_frames" },
        startFrame: { type: "number", description: "Range start frame (>= 1)" },
        endFrame: { type: "number", description: "Range end frame" },
        anchorFrame: { type: "number", description: "Anchor frame for scale_range (default: startFrame)" },
        factor: { type: "number", description: "Scale multiplier for scale_range (e.g. 1.5 slows down, 0.5 speeds up)" },
        newStartFrame: { type: "number", description: "Alternative destination start frame for scale_range" },
        newEndFrame: { type: "number", description: "Alternative destination end frame for scale_range" },
        valueOffset: { description: "Numeric or vector/color delta added to every key in range for relative_offset" },
      },
    },
  },
  {
    name: "animation_tween",
    rpcMethod: "animation.tween",
    description: "Generate a weighted breakdown (0..1), anticipation (weight < 0), or overshoot (weight > 1) keyframe at `frame` interpolated between surrounding keyframes across one or more channels.",
    inputSchema: {
      type: "object",
      required: ["frame"],
      properties: {
        ...ANIM_CHANNEL_SELECTOR_PROPS,
        channels: { type: "array", items: {}, description: "Optional list of channel names on the selected layer/bone to tween together" },
        targets: {
          type: "array",
          description: "Optional explicit list of channel targets to tween together",
          items: { type: "object", properties: { ...ANIM_CHANNEL_SELECTOR_PROPS } },
        },
        frame: { type: "number", description: "Target breakdown frame (>= 1)" },
        weight: { type: "number", description: "Interpolation weight: 0.5 midpoint, < 0 anticipation, > 1 overshoot (default: 0.5)" },
        prevFrame: { type: "number", description: "Optional explicit previous keyframe override" },
        nextFrame: { type: "number", description: "Optional explicit next keyframe override" },
        ...INTERP_PROPS,
      },
    },
  },
  {
    name: "timeline_markers",
    rpcMethod: "timeline.markers",
    description: "List, add, update, delete, or clear document-wide (`MohoDoc.fTimelineMarkers`) or layer-specific (`MohoLayer.fTimelineMarkers`) timeline markers with color tags.",
    inputSchema: {
      type: "object",
      required: ["operation"],
      properties: {
        ...LAYER_SELECTOR_PROPS,
        scope: { type: "string", enum: ["document", "layer"], description: "Marker scope (defaults to 'layer' if layer selector passed, else 'document')" },
        operation: { type: "string", enum: ["list", "add", "update", "delete", "clear"], description: "Timeline marker operation" },
        frame: { type: "number", description: "Target frame for add, update, or delete" },
        label: { type: "string", description: "Marker text label" },
        text: { type: "string", description: "Alias for label" },
        colorTag: { type: "number", description: "Marker color tag index (InterpSetting.tags)" },
      },
    },
  },
  {
    name: "action_list",
    rpcMethod: "action.list",
    description: "List Regular and Smart Bone Actions on a layer (including isSmartBone, angleSweepDeg, and is360SmartBone flags) and report the active layer/document action.",
    inputSchema: { type: "object", properties: { ...LAYER_SELECTOR_PROPS } },
  },
  {
    name: "action_activate",
    rpcMethod: "action.activate",
    description: "Enter or create an Action / Smart Bone Action on a layer (synced with SetCurrentDocAction; pass '' to return to Mainline).",
    inputSchema: {
      type: "object",
      required: ["actionName"],
      properties: {
        ...LAYER_SELECTOR_PROPS,
        actionName: { type: "string", description: "Action/Bone name, or '' to return to Mainline" },
      },
    },
  },
  {
    name: "action_createSmartBone",
    rpcMethod: "action.createSmartBone",
    description: "Create a standard or full +/-360-degree Smart Bone Action (exact unwrapped zeroAngle +/- 2*pi, 96-frame default duration, linear bone keys, optional Frame-0-to-end mirroring across child layers).",
    inputSchema: {
      type: "object",
      properties: {
        ...BONE_SELECTOR_PROPS,
        mode: { type: "string", enum: ["standard", "360"], description: "Default: 'standard'; '360' enforces exact unwrapped +/-360 deg sweep" },
        actionName: { type: "string", description: "Optional explicit action name (defaults to boneName or 'boneName 2' when direction='second')" },
        direction: { type: "string", enum: ["first", "second"], description: "'second' creates the '<BoneName> 2' reverse action" },
        duration: { type: "number", description: "Action length in frames (default: 96)" },
        startFrame: { type: "number", description: "Start frame (default: 1)" },
        endFrame: { type: "number", description: "End frame (defaults to duration)" },
        deltaAngleDeg: { type: "number", description: "Relative angle delta in degrees from Frame 0 angle (default: +90 for standard, +/-360 for 360 mode)" },
        targetAngleDeg: { type: "number", description: "Absolute target angle in degrees (standard mode only)" },
        clockwise: { type: "boolean", description: "In 360 mode, sweep -360 deg instead of +360 deg when deltaAngleDeg omitted" },
        addMidpointKey: { type: "boolean", description: "In 360 mode, also place a midpoint +/-180 deg linear key" },
        interpolation: { type: "string", enum: INTERP_ENUM, description: "Driving bone interpolation (default: 'linear')" },
        mirrorFrame0ToEnd: { type: "boolean", description: "Copy Frame 0 transforms and vector point positions to endFrame (and startFrame) for clean 360 turnarounds" },
        mirrorFrame0ToStart: { type: "boolean", description: "Also mirror Frame 0 to startFrame when mirrorFrame0ToEnd=true (default: true)" },
        mirrorLayers: { type: "array", description: "Optional specific layer names/IDs to mirror (defaults to all child layers under the BoneLayer)", items: {} },
        leaveActive: { type: "boolean", description: "Keep the newly created Smart Bone Action active for immediate pose editing (default: false -> returns to Mainline)" },
      },
    },
  },
  {
    name: "action_manage",
    rpcMethod: "action.manage",
    description: "Insert (copy or reference), rename, delete, or blend Actions on a layer.",
    inputSchema: {
      type: "object",
      required: ["operation"],
      properties: {
        ...LAYER_SELECTOR_PROPS,
        operation: { type: "string", enum: ["insert", "rename", "delete", "blend"], description: "Action management operation" },
        actionName: { type: "string", description: "Target action name (for insert, rename, delete)" },
        newName: { type: "string", description: "New action name (required for rename)" },
        frame: { type: "number", description: "Target frame for insert or blend (default: current frame)" },
        byReference: { type: "boolean", description: "For insert: true inserts reference, false copies keyframes (default: false)" },
        actionNames: { type: "array", items: { type: "string" }, description: "For blend: action names to blend" },
        weights: { type: "array", items: { type: "number" }, description: "For blend: 0..1 blend weight per action" },
        actionFrames: { type: "array", items: { type: "number" }, description: "For blend: optional per-action source frame" },
        relative: { type: "boolean", description: "For blend: add blended pose relative to current pose" },
        blendMode: { type: "number", description: "For blend: Moho 6-arg BlendActions mode code" },
      },
    },
  },
  {
    name: "camera_get",
    rpcMethod: "camera.get",
    description: "Read camera track, zoom, rollDeg, and panTiltDeg at a given frame.",
    inputSchema: {
      type: "object",
      properties: {
        frame: { type: "number", description: "Frame at which to sample camera state (default: current frame)" },
      },
    },
  },
  {
    name: "camera_setKeyframe",
    rpcMethod: "camera.setKeyframe",
    description: "Set camera track, zoom, rollDeg, and/or panTiltDeg keyframes with optional interpolation.",
    inputSchema: {
      type: "object",
      properties: {
        frame: { type: "number", description: "Target frame for camera keyframes (default: current frame)" },
        track: { type: "object", description: "Camera position {x, y, z}", properties: { x: { type: "number" }, y: { type: "number" }, z: { type: "number" } } },
        zoom: { type: "number", description: "Camera zoom angle in degrees (default: 60)" },
        rollDeg: { type: "number", description: "Camera roll angle in degrees" },
        panTiltDeg: { type: "object", description: "Camera pan/tilt angles in degrees {x, y}", properties: { x: { type: "number" }, y: { type: "number" } } },
        ...INTERP_PROPS,
      },
    },
  },
];
