// Moho Pro 14.4 rigging, shading, animation, and glTF rules exposed via MCP resource `moho-studio://playbook`.
// Pure ASCII, zero runtime dependencies.

export const PLAYBOOK_TEXT = `# Moho Pro 14.4 Authoring Playbook (moho-studio://playbook)

16 practical rules for rigging, character performance, vector shading, animation, and glTF export in Moho Pro 14.4, plus live-verified Lua runtime invariants.

## 1. Zero-Strength Dials, Targets and Hierarchy Isolation
- Create control dials, IK targets, and Pin Bones with \`strength: 0\` (for Pin Bones set \`pinBone: true\` or \`length: 0\`) so they never deform nearby artwork.
- Do not rigid-bind (\`layer_bindToBone\`) a parent GroupLayer when any child inside it needs its own bone (for example, keep \`back_hair\` outside a rigid-bound \`Head\` group or bind children individually).

## 2. Flood-Then-Override Point Binding
- Flood-bind an entire limb or torso mesh to its primary bone first, then override only the joint or crease vertices onto adjacent bones (or use Flexi-Bind where smooth stretching is wanted).

## 3. Pre-Bent 2-Bone IK, Unparented Targets and Thigh Proxy Isolation
- Pre-bend 2-bone IK limbs slightly toward the natural knee or elbow angle on Frame 0 so the IK solver does not flip backward.
- Keep ankle/foot IK target bones unparented (\`parentBoneId: -1\`) so feet stay planted in world space, and set \`fixedAngle: true\` on foot bones for flat floor contact.
- Use 3-bone Flexi-Bind (or 2-bone Smooth Joint on simple sleeves/bitmaps) intentionally, and isolate IK thigh proxy bones when driving coats or skirts so hip motion does not drag unrelated geometry.

## 4. 96-Frame Linear Smart Bones and +/-360-Degree Turnarounds
- Author Smart Bone Actions at \`duration: 96\` frames with \`interpolation: "linear"\` on the driving bone angle so scrubbing stays uniform.
- Split bidirectional controls into \`<BoneName>\` and \`<BoneName> 2\` Actions.
- For 360-degree turnarounds or 360 walk-cycle dials, call \`action_createSmartBone\` with \`mode: "360"\` (exact unwrapped \`zeroAngle +/- 2*pi\`, never mod-360 wrapped) and \`mirrorFrame0ToEnd: true\` so Frame 96 matches Frame 0 cleanly.

## 5. Scoped Animated Layer Order (Avoid Action Collisions)
- Enable Animated Layer Order (\`layer_setLayerOrder\`) only on the narrowest GroupLayer that owns the reordering layers.
- Never keyframe layer order on the same GroupLayer from two separate Smart Bone Actions (such as \`Head_LR\` and \`Body_LR\`); split head and body into separate child Groups.

## 6. Quad Warp, Regular Curver, Compressible Curver and Dual-Curver
- Quad Smart Warp (\`mesh_createSmartWarp(mode="quad")\`, \`continuousTriangulation: false\`): perspective panels, boxy props, and 4-corner bitmap warps.
- Regular Curver (\`mode: "curver"\`): tails, ribbons, ropes, and hair strands along an open spine; tune influence radius with \`curverWidth\` (\`pt.fWidth\`) and add segments with \`mesh_editTopology(operation="split_segments")\`.
- Compressible Curver (\`compressible: true\`): squash/stretch compression along the spine length for accordions, caterpillars, or elastic limbs.
- Dual/Multi-Curver (\`appendToLayerId\` / \`appendToLayerName\`): place paired curves (such as \`+/-0.5\` bounds) on one Curver layer for volumetric cheeks or limbs.
- Bind the Warp or Curver layer to its driving bone (\`autoBindToTargetBone: true\`).

## 7. Vitruvian Bone Groups Hold Root Sub-Chain Bones Only
- Add only the root bone of each swappable sub-chain (for example \`Arm_Front_Upper\` and \`Arm_Side_Upper\`) into a Vitruvian \`M_BoneGroup\` via \`bone_manageGroup\`; Moho hides and reveals each root bone's descendants automatically.

## 8. Painterly Vector Shading
- Build 4-point ovals or clean primitives, group base and shading layers with \`layer_groupSelection(maskPreset="mask_inside_bottom")\`, and set \`layer_setMasking(excludeStrokes=true)\` on the base layer so outlines stay sharp over interior shading.
- Stack \`softEdgePx\` or \`gradient\` shapes for volume, keep one Blending Mode per VectorLayer (\`multiply\` for shadows, \`screen\` or \`add\` for highlights), and place unmasked cast shadows beneath the base layer.

## 9. Liquid Shapes and Top-Shape Blend Precedence
- Use \`mesh_liquidShapes\` (\`add\`, \`subtract\`, \`intersect\` / \`clip\`) for mask-free pupils inside eyes, 2.5D mouth cutouts, movable cel lighting, and counter-rotating VFX cutters.
- The topmost shape in a Liquid Shape cluster governs blend radius and style precedence. Pair \`intersect\` with \`mesh_editTopology(operation="merge_shapes")\` when flattening static silhouettes.

## 10. Smart Line Boil and Staggered Frame Intervals
- Set \`smartBoilInterval: 0\` (motion-triggered boil) with \`randomize: true\` on Moho 14 Brush styles so held frames stay still while moving lines boil naturally.
- Keyframe characters on twos or threes (\`interval: 2\` or \`3\`) while keeping camera pans on ones (\`interval: 1\`) to avoid strobing pans.

## 11. Dual-Style Setup and 2x Stroke-Behind-Fill
- Assign \`Style 1\` for shared outlines/brush/boil and \`Style 2\` for shared fills via \`style_manage(operation="new_from_shape", matchLineWidth=false)\` so shapes with different line weights share one global color style.
- Use \`mesh_createShape(pointIds=[...])\` on partial edge subsets to stack independent strokes; calling \`CreateShape\` on all edges of an existing shape updates it in place, while a partial edge subset creates a separate shape.

## 12. Curve-Bound Particle Wave Rigs
- Place an open vector emitter curve at the bottom (\`Layer(0)\`) of a \`ParticleLayer\`, set \`useBaseLayerAsSource: true\`, \`lifetime: 0\` (or a tuned frame count), \`playbackTimeShift\`, \`emitInOrder: true\`, and taper emitter \`pt.fWidth\` for ribbons, rain sheets, and flowing trails.

## 13. Loop Cycles, Follow-Through, Anticipation and Pre-Roll
- Build clean loops with \`animation_createCycle\` so \`endFrame\` copies \`startFrame\` and cycles back to \`startFrame + 1\` (Frame 2 when starting at Frame 1); cycling back to Frame 1 repeats the start pose for 2 frames and stutters.
- Add secondary motion with staggered follow-through (\`+6f\` / \`+12f\`), amplified delayed constraints (\`110-120%\` scale with positive \`delay\`), negative-delay anticipation (\`-6f\`), weighted breakdowns/overshoots (\`animation_tween\`), and an 18-24 frame pre-roll (\`startFrame: 24\`) so Bone Dynamics and Particles settle before output Frame 1.

## 14. glTF 2.0 and Game-Engine Export Rules
- Run \`rig_auditGltf\` before \`document_exportGltf\`.
- Moho glTF exports vector layers as rasterized meshes/textures: raw vector point animation freezes unless driven by bones/Smart Warp proxies or baked with \`fbf: true\`.
- Author game-engine Regular Actions in-place (zero root translation drift) and split jumps into 4 clips (anticipation, rise, apex/fall, land). Use \`gltf_*\` layer \`userTags\` (\`gltf_comp\`, \`gltf_nomesh\`, \`gltf_nowarp\`, \`gltf_nobones\`, \`gltf_blend\`, \`gltf_skinned\`, \`gltf_render\`) for per-layer overrides.

## 15. Visual Verification and Moho 14.4 Lua Safety Notes
- Do not rely on \`document_captureWindow\` alone to check Masks, Layer Outlines, Point Colors, Merged-Alpha brushes, Soft Edge, or mid-timeline Bone Dynamics; render and inspect with \`document_renderFrame\` or \`document_cliRender\`.
- In custom \`lua_execute\` scripts: read/write \`M_Style\` names only via \`style:Name()\` / \`style:SetName(name)\` (never access \`style.fName\`, which corrupts \`tolua_ubox\` into \`LM_String\`), pass \`LM.String\` userdata (never a Lua string) to \`LayerComp:SetName(lmStr)\`, cast \`AnimChannel:ActionByName(name)\` with \`moho:ChannelAsAnimVal\` / \`ChannelAsAnimVec3\`, pass component index \`0/1/2\` as arg #1 to \`InterpSetting\` Bezier methods, and use \`document_close(force=true)\` to close dirty disposable documents without blocking on a Save prompt.

## 16. Control-First Studio Rigging and Character Performance
- Before animating ANY existing Moho character rig, call \`rig_getControls\` first. Drive performances through the rig's existing Smart Bone Dials (\`body\`, \`head\`, \`blink\`, \`mouth\`, \`brows\`, \`hands\`), Foot/Hand IK Targets, SwitchLayers, Vitruvian Bone groups, and Regular Actions instead of dragging raw vector vertices or overriding bound layers on Mainline.
- When building a new studio character rig, place animator-ready Smart Bone Dials beside the character using \`bone_createSmartDial\` (\`Blink\`, \`Mouth Open\`, \`Head Turn\`, \`Body Turn\`, \`Eyebrows\`) with \`strength: 0\`, \`ignoredByIK: true\`, \`showLabel: true\`, explicit angle limits, and \`duration: 96\` linear actions, plus unparented Foot IK Targets (\`fixedAngle: true\` on foot bones).
- Standard studio motion patterns:
  - Eye blinks: 2 frames close, 1 to 2 frames held shut, 3 to 4 frames ease-out open on the \`Blink\` Smart Bone Dial (pair with a subtle brow dip).
  - Mouth and speech: keyframe a \`Mouth\` SwitchLayer with \`switch_importLipSync\` (Papagayo or Rhubarb) or drive \`Mouth Open\` / \`Mouth Mood\` Smart Bone Dials 1 to 2 frames ahead of audio beats.
  - Walk cycles: build a 24-frame loop (12 frames per step) on Foot IK Targets (Contact -> Down -> Passing -> Up -> Contact) with vertical root bob, opposite arm swing, 2 to 4 frame wrist/hand follow-through, and \`animation_createCycle\` looping back to \`startFrame + 1\`.
  - Arm and body gestures: move in curved arcs leading from chest/shoulder to elbow to wrist, and use \`animation_tween\` for breakdowns, anticipation (\`weight < 0\`), and overshoot (\`weight > 1\`).
`;
