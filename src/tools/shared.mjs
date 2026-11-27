// Shared JSON Schema fragments reused across Moho tool definitions.

export const LAYER_SELECTOR_PROPS = {
  layerId: { type: "number", description: "Numeric depth-first layer ID (from layer_list)" },
  layerName: { type: "string", description: "Exact layer name" },
  layerUuid: { type: "string", description: "Layer UUID" },
};

export const BONE_SELECTOR_PROPS = {
  ...LAYER_SELECTOR_PROPS,
  boneId: { type: "number", description: "Zero-based bone index inside the BoneLayer" },
  boneName: { type: "string", description: "Exact bone name" },
};

export const INTERP_ENUM = [
  "smooth",
  "linear",
  "ease",
  "ease_in",
  "ease_out",
  "ease_in_out",
  "step",
  "cycle",
  "pose",
  "bezier",
  "noisy",
  "bounce",
  "elastic",
  "stagger",
];

export const BLEND_MODE_ENUM = [
  "normal",
  "multiply",
  "screen",
  "overlay",
  "add",
  "difference",
  "hue",
  "saturation",
  "color",
  "luminosity",
  "soft_light",
  "color_dodge",
  "linear_dodge",
  "color_burn",
];

export const MASKING_MODE_ENUM = [
  "masked",
  "not_masked",
  "add_mask",
  "sub_mask",
  "add_mask_invis",
  "sub_mask_invis",
  "clear_add_mask",
  "clear_add_mask_invis",
];

export const GEOM_REF_SCHEMA = {
  type: "object",
  description: "Snap bone endpoint to a layer anchor, vector point, or shape centroid (auto-transformed into BoneLayer space)",
  properties: {
    ...LAYER_SELECTOR_PROPS,
    pointId: { type: "number", description: "Vector point index on VectorLayer" },
    shapeId: { type: "number", description: "Shape index whose point centroid to use" },
    anchor: {
      type: "string",
      enum: ["center", "origin", "top", "bottom", "left", "right", "top_left", "top_right", "bottom_left", "bottom_right"],
      description: "Bounds/origin anchor when pointId/shapeId omitted (default: 'center')",
    },
    offsetX: { type: "number" },
    offsetY: { type: "number" },
  },
};

export const RGBA_SCHEMA = {
  type: "object",
  description: "RGBA color object using either 0..255 byte values or 0.0..1.0 normalized floats",
  properties: {
    r: { type: "number", description: "Red channel (0..255 or 0..1)" },
    g: { type: "number", description: "Green channel (0..255 or 0..1)" },
    b: { type: "number", description: "Blue channel (0..255 or 0..1)" },
    a: { type: "number", description: "Alpha channel (default: opaque)" },
  },
};

export const GRADIENT_SCHEMA = {
  type: "object",
  description: "Moho fill gradient effect configuration",
  properties: {
    type: { type: "string", enum: ["linear", "radial", "reflected", "angle"], description: "Gradient geometry type" },
    allowTransparency: { type: "boolean", description: "Honor per-stop alpha transparency" },
    stops: {
      type: "array",
      description: "Ordered gradient color stops",
      items: {
        type: "object",
        required: ["pos", "color"],
        properties: {
          pos: { type: "number", description: "Gradient stop position (0.0 .. 1.0)" },
          color: RGBA_SCHEMA,
        },
      },
    },
  },
};

export const BRUSH_SCHEMA = {
  type: "object",
  description: "Moho Pro 14 vector brush stroke parameters",
  properties: {
    name: { type: "string", description: "Brush preset name from style_manage(list_brushes), or '' to clear" },
    spacing: { type: "number", description: "Brush stamp spacing percentage" },
    jitter: { type: "number", description: "Angular jitter amount (0..1)" },
    align: { type: "boolean", description: "Align brush stamps along the curve tangent" },
    randomOrder: { type: "boolean", description: "Randomize multi-dab brush image order" },
    mergedAlpha: { type: "boolean", description: "Prevent overlapping stamp darkening (fBrushMergeAlpha)" },
    mergeAlpha: { type: "boolean", description: "Alias for mergedAlpha" },
    randomize: { type: "boolean", description: "Enable random brush boil/jitter mode (fBrushRandomize)" },
    isColor: { type: "boolean", description: "Use brush bitmap colors directly" },
    tint: { type: "boolean", description: "Tint brush using shape stroke color" },
    angleDrift: { type: "number", description: "Rotation drift along the stroke" },
    sizeVarAmplitude: { type: "number", description: "Stroke width variation amplitude" },
    sizeVarScale: { type: "number", description: "Stroke width variation scale" },
    hueDrift: { type: "number", description: "Hue drift along the stroke" },
    satDrift: { type: "number", description: "Saturation drift along the stroke" },
    valDrift: { type: "number", description: "Brightness/value drift along the stroke" },
    smartBoilInterval: { type: "number", description: "Smart Line Boil interval (0 = motion-triggered in Moho 14)" },
  },
};

export const INTERP_PROPS = {
  interpolation: { type: "string", enum: INTERP_ENUM, description: "Keyframe interpolation mode (e.g. smooth, linear, ease, step, bezier, cycle)" },
  cycleBack: { type: "number", description: "Relative frame delta for Cycle interpolation (default: frame - 2, loops back to Frame 2)" },
  cycleMode: { type: "string", enum: ["relative", "absolute"], description: "Cycle targeting mode: 'relative' (val1 delta, val2=-1) or 'absolute' (val2 frame)" },
  cycleTargetFrame: { type: "number", description: "Target loop frame when using Cycle interpolation" },
  val1: { type: "number", description: "InterpSetting.val1 (relative cycle delta or noisy/bounce/elastic param)" },
  val2: { type: "number", description: "InterpSetting.val2 (absolute cycle target frame when >= 0, -1 for relative)" },
  interval: { type: "number", description: "Step interval in frames (1 = ones, 2 = twos, 3 = threes)" },
  stagger: { type: "boolean", description: "Enable Moho Stagger step interpolation flag" },
  hold: { type: "number", description: "Frames to hold prior value before interpolating" },
  additiveCycle: { type: "boolean", description: "Enable additive cycle accumulation" },
  colorTag: { type: "number", description: "Keyframe color tag index (InterpSetting.tags)" },
  bezierInAngle: { type: "number", description: "Bezier incoming tangent angle (radians, InterpSetting:SetBezierInAngle)" },
  bezierInPercent: { type: "number", description: "Bezier incoming handle percentage (InterpSetting:SetBezierInPercentage)" },
  bezierOutAngle: { type: "number", description: "Bezier outgoing tangent angle (radians, InterpSetting:SetBezierOutAngle)" },
  bezierOutPercent: { type: "number", description: "Bezier outgoing handle percentage (InterpSetting:SetBezierOutPercentage)" },
};

export const ANIM_CHANNEL_ENUM = [
  "translation",
  "translation_x",
  "translation_y",
  "translation_z",
  "scale",
  "scale_x",
  "scale_y",
  "scale_z",
  "rotationZ",
  "rotationX",
  "rotationY",
  "opacity",
  "visibility",
  "blur",
  "follow_path",
  "layer_order",
  "switch",
  "bone_angle",
  "bone_pos",
  "bone_pos_x",
  "bone_pos_y",
  "bone_scale",
  "bone_dynamics",
  "bone_flip_h",
  "bone_flip_v",
  "bone_target",
  "vitruvian_active_bone",
  "wind_strength",
  "wind_direction",
  "wind_turbulent_amplitude",
  "wind_turbulent_frequency",
  "gravity_strength",
  "gravity_direction",
  "point_pos",
  "point_pos_x",
  "point_pos_y",
  "point_width",
  "point_curvature",
  "shape_color",
  "shape_fill_color",
  "shape_stroke_color",
  "combo_blend",
  "camera_track",
  "camera_track_x",
  "camera_track_y",
  "camera_track_z",
  "camera_zoom",
  "camera_roll",
  "camera_pantilt",
];

export const ANIM_CHANNEL_SELECTOR_PROPS = {
  ...BONE_SELECTOR_PROPS,
  channel: { type: "string", enum: ANIM_CHANNEL_ENUM, description: "Target Moho animation channel name (supports *_x/*_y/*_z Separate Dimensions shortcuts)" },
  dimension: { type: "string", enum: ["x", "y", "z"], description: "Separate Dimension axis for vector channels (x, y, z)" },
  splitDimensions: { type: "boolean", description: "Split vector channel dimensions automatically if not already split" },
  pointId: { type: "number", description: "Zero-based point index for point_pos/point_width/point_curvature" },
  curveIndex: { type: "number", description: "Curve index on point for point_curvature (default: 0)" },
  shapeId: { type: "number", description: "Zero-based shape index for shape_* / combo_blend channels" },
  shapeName: { type: "string", description: "Shape name for shape_* / combo_blend channels" },
  groupIndex: { type: "number", description: "Vitruvian group index for vitruvian_active_bone" },
  groupName: { type: "string", description: "Vitruvian group name for vitruvian_active_bone" },
};
