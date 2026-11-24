# Verified Moho Pro 14.4 Lua 5.4 API Reference

Lua 5.4 signatures, constants, and runtime edge cases verified against Moho Pro 14.4's bundled scripts (`Resources\Support\Scripts\`) and live execution on Windows x64.

## Method Signatures and Parameter Notes

| Class | Signature | Notes |
| :--- | :--- | :--- |
| `ScriptInterface` | `DuplicateLayer(layer: MohoLayer, asReference?: bool) -> MohoLayer` | `asReference` defaults to `false`; `true` creates a live Referenced Layer. |
| `ScriptInterface` | `FileClose() -> void` | Opens a blocking Save prompt if the document is dirty. See Modal Safety below. |
| `ScriptInterface` | `FileImport(path: string, mode?: int) -> void` | `mode` defaults to `0`. For `.svg`, Moho 14's bundled `SS_SVGImport` produces cleaner vector hierarchies. |
| `ScriptInterface` | `FileRender(path: string) -> void` | Renders the current frame to PNG. Call `SetCurFrame(frame)` and `UpdateUI()` first. |
| `ScriptInterface` | `ChannelAsAnimVal(ch: AnimChannel) -> AnimVal` | Needed before calling `:GetValue()` on channels returned by `AnimChannel:ActionByName(name)` (also `ChannelAsAnimVec3`, `ChannelAsAnimVec2`). |
| `MohoDoc` | `BackCol() -> LM.rgb_color` | Named `BackCol`, not `BackColor`. Returns a 4-byte `LM.rgb_color`. |
| `MohoDoc` | `SetBackCol(color: LM.rgb_color) -> void` | Must receive `LM.rgb_color`, not `LM.ColorVector`. |
| `MohoDoc` | `GetLayerComp(index: int) -> LayerComp` | Zero-based index bounded by `CountLayerComps()`. |
| `MohoDoc` | `AddLayerCompWithName(name: string) -> LayerComp` | Creates and returns a new `LayerComp`. |
| `MohoDoc` | `DeleteLayerComp(index: int) -> void` | Takes a 0-based `int` index, not a string or `LayerComp` object. |
| `MohoDoc` | `ApplyLayerComp(comp: LayerComp, frame?: int, rootLayer?: MohoLayer) -> void` | Takes `LayerComp` userdata, integer frame (default `0`), and optional root layer. |
| `LayerComp` | `SetName(inName: LM.String) -> void` | Must receive an `LM.String` userdata, never a Lua `string`. Passing a Lua string segfaults Moho 14.4. |
| `MohoLayer` | `SetLayerParentBone(boneId: int) -> void` | Rigid layer-to-bone binding (not `SetParentBone`). |
| `MohoLayer` | `AddToFlexiBoneSubset(boneId: int) -> void` | Call `ClearFlexiBoneSubset()` first, add bone IDs, then `EnableFlexiBoneSubset()`. |
| `MohoLayer` | `MarkFlexiBoneSubsetAsElbow(isElbow: bool) -> void` | Enables 2-bone elbow / smooth joint mode on the flexi-bone subset. |
| `MohoLayer` | `EnableFlexiBoneSubset() -> void` / `DisableFlexiBoneSubset() -> void` | Toggles flexi-bone subset binding on the controlling skeleton. |
| `MohoLayer` | `SetMaskingMode(mode: int) -> void` | Uses `MOHO.MM_*` constants (`0..7`). |
| `MohoLayer` | `SetMaskExpansion(expandByPixel: bool) -> void` | Boolean flag ("Expand mask by a pixel"), not a pixel radius. |
| `MohoLayer` | `RenderLayerImage(options: MohoLayerRenderOptions) -> bool` | Renders an isolated transparent PNG; outputs file path in `options.imagePath` and world bounds in `options.layerBounds`. |
| `MohoLayer` | `IsSmartBoneAction(name: string) -> bool` | True when `name` matches a Smart Bone Action on this layer. |
| `MohoLayer` | `InsertAction(name: string, frame: int, byReference?: bool) -> void` | Inserts action keys at `frame` (`byReference=false` copies, `true` references). |
| `MohoLayer` | `RenameAction(oldName: string, newName: string) -> void` | Renames an action on the layer. |
| `MohoLayer` | `DeleteAction(name: string) -> void` | Deletes an action from the layer. |
| `MohoLayer` | `BlendActions(frame: int, modeOrRelative: bool/int, count: int, names: table, weights: table [, frames: table]) -> void` | Two overloads: 5-arg (`relative: bool`) and 6-arg (`mode: int` + per-action frame array). Pass `LM.String` elements in `names`. |
| `MohoLayer` | `SetWarpLayer(warpLayer: MohoLayer\|nil) -> void` | Links or unlinks (`nil`) a Smart Warp or Curver `MeshLayer`. |
| `MeshLayer` | `SetContinuousTriangulation(enabled: bool) -> void` | Enables live Smart Warp triangulation on a vector mesh. |
| `MeshLayer` | `MarkAsWarpLayer(isWarp: bool, doc: MohoDoc) -> void` | Requires 2nd argument `moho.document`; omitting it passes NULL. |
| `MeshLayer` | `MarkAsCurver(isCurver: bool) -> void` | Marks a vector layer as a Moho 14 Curver deformer. |
| `MeshLayer` | `UpdateWarpLayer() -> void` | Rebuilds internal Smart Warp triangulation bindings. |
| `MeshLayer` | `fExcludeLinesFromMask` / `fSquashableCurveDeformer` | Direct `bool` fields on `MeshLayer` in Moho 14.4. |
| `GroupLayer` | `SetGroupMask(mode: int) -> void` | Uses `MOHO.GROUP_MASK_NONE=0`, `GROUP_MASK_SHOW_ALL=1`, `GROUP_MASK_HIDE_ALL=2`. |
| `GroupLayer` | `EnablePhysics(frame: int, enabled: bool) -> void` | Frame comes first, boolean second. |
| `GroupLayer` | `SetPhysicsGravity(gravity: LM.Vector2) -> void` | Takes `LM.Vector2`, not two separate floats. |
| `GroupLayer` | `UseBakedPhysics(baked: bool) -> void` | Enables or disables baked physics keyframes on the group. |
| `M_Mesh` | `CombineShapes(base: M_Shape, other: M_Shape, comboMode: int, blend: float, flag?: bool) -> int` | Liquid Shapes boolean combination (`MOHO.COMBO_*`). Returns the new shape ID. |
| `M_Mesh` | `BakeCombinedShapes(shape: M_Shape, flag?: bool) -> int` | Bakes a Liquid Shapes cluster into a single vector shape. Returns the new shape ID. |
| `M_Style` | `Name() -> string` / `SetName(name: string) -> void` | Always use `:Name()` and `:SetName()`. Never touch `style.fName` (see gotcha #1). |
| `InterpSetting` | `BezierInAngle(comp: int)` / `SetBezierInAngle(comp: int, angle: number)` | All 4 Bezier handle getters/setters (`InAngle`, `InPercentage`, `OutAngle`, `OutPercentage`) take component index (`0` = scalar/X, `1` = Y, `2` = Z) as arg #1. |

## MOHO Constants

| Group | Values |
| :--- | :--- |
| Layer Types (`MOHO.LT_*`) | `LT_UNKNOWN=0`, `LT_VECTOR=1`, `LT_IMAGE=2`, `LT_GROUP=3`, `LT_BONE=4`, `LT_SWITCH=5`, `LT_PARTICLE=6`, `LT_NOTE=7`, `LT_3D=8`, `LT_AUDIO=9`, `LT_PATCH=10`, `LT_TEXT=11` (Frame-by-Frame is `LT_SWITCH` with `SetFBFLayer(true)`) |
| Interpolation (`MOHO.INTERP_*`) | `INTERP_LINEAR=0`, `INTERP_SMOOTH=1`, `INTERP_EASE=2` (Ease In/Out), `INTERP_STEP=3`, `INTERP_NOISY=4`, `INTERP_CYCLE=5`, `INTERP_POSE=6`, `INTERP_EASE_IN=7`, `INTERP_EASE_OUT=8`, `INTERP_BEZIER=9`, `INTERP_BOUNCE=10`, `INTERP_ELASTIC=11` |
| InterpSetting Flags | `stagger`, `hold`, `tags`, `IsAdditiveCycle()`, `SetAdditiveCycle(bool)` |
| Masking (`GROUP_MASK_*`, `MM_*`) | `GROUP_MASK_NONE=0`, `GROUP_MASK_SHOW_ALL=1`, `GROUP_MASK_HIDE_ALL=2`; `MM_MASKED=0`, `MM_NOTMASKED=1`, `MM_ADD_MASK=2`, `MM_SUB_MASK=3`, `MM_ADD_MASK_INVIS=4`, `MM_SUB_MASK_INVIS=5`, `MM_CLEAR_ADD_MASK=6`, `MM_CLEAR_ADD_MASK_INVIS=7` |
| Liquid Shapes (`MOHO.COMBO_*`) | `COMBO_NORMAL=0`, `COMBO_ADD=1`, `COMBO_SUBTRACT=2`, `COMBO_INTERSECT=3` |
| Blending Modes (`MOHO.BM_*`) | `BM_NORMAL=0`, `BM_MULTIPLY=1`, `BM_SCREEN=2`, `BM_OVERLAY=3`, `BM_ADD=4`, `BM_DIFFERENCE=5`, `BM_HUE=6`, `BM_SATURATION=7`, `BM_COLOR=8`, `BM_LUMINOSITY=9`, `BM_SOFT_LIGHT=10`, `BM_COLOR_DODGE=11`, `BM_LINEAR_DODGE=12`, `BM_COLOR_BURN=13` |
| Project DOF (`MOHO.MohoGlobals`) | `ProjDofEnabled`, `ProjDofFocusDist`, `ProjDofFocusRange`, `ProjDofMaxBlur` |

## Headless CLI Renderer (`Moho.exe -r`)

```text
Moho.exe -r <project.moho> -v -f <PNG|MP4|MOV|AnimatedGIF|JPEG|BMP|TGA|PSD|SVG>
  -start <N> -end <N>
  -outfolder <dir> | -o <outputFile>
  [-layercomp <name>] [-createfoldersforlayercomps yes|no] [-addlayercompsuffix yes|no]
  [-halfsize yes|no] [-halffps yes|no] [-aa yes|no] [-shapefx yes|no] [-layerfx yes|no]
  [-extrasmooth yes|no] [-premultiply yes|no] [-multithread yes|no] [-log <file>]
```

## Runtime Gotchas in Moho Pro 14.4

### 1. `M_Style.fName` corrupts `tolua_ubox`

`M_Style::fName` sits at offset `+0x0` of `M_Style` (`&(style->fName) == (void*)style`). Reading `style.fName` from Lua causes `tolua++`'s pointer cache (`tolua_ubox`) to overwrite the `M_Style` userdata's metatable with `LM_String`, breaking every subsequent method or field access on that style. Guard style pointers with `tolua.cast(st, "M_Style")` and always use `style:Name()` and `style:SetName(name)`.

### 2. `LayerComp:SetName` crashes on Lua strings

Moho 14.4's release `tolua++` binding for `LayerComp:SetName` expects an `LM.String` userdata without a runtime type guard. Passing a plain Lua string evaluates to `NULL` inside C++ and causes an immediate access violation. Always wrap the string first:

```lua
local s = LM.String:new_local()
s:Set(newName)
comp:SetName(s)
```

### 3. `FileClose()` blocks on dirty documents

`MohoDoc:SetDirty()` takes no arguments and only marks a document dirty; there is no Lua method to clear the dirty flag. Calling `moho:FileClose()` on an unsaved dirty document blocks on a native Save prompt. To discard a disposable document non-interactively, save it to a temporary `.moho` path with `moho:FileSaveAs(tmpPath)`, call `moho:FileClose()`, and delete `tmpPath` with `os.remove`.

### 4. `AnimChannel:ActionByName` returns a base `AnimChannel`

The userdata returned by `channel:ActionByName(name)` does not expose typed `:GetValue()`. Cast it first with `moho:ChannelAsAnimVal(ch)` or `moho:ChannelAsAnimVec3(ch)` before reading keyframe values.

### 5. `M_BoneGroup.fActiveBone` invalidates the group handle

Accessing `grp.fActiveBone` on an `M_BoneGroup` userdata works once (returning an `AnimVal`) and then invalidates subsequent lookups on that same Lua `grp` reference. Read all `grp` methods (`Name`, `CountBones`, `Bone`, `ActiveBone`, `fEnabled`) first, read `grp.fActiveBone` last into a local variable, and re-fetch `skel:Group(idx)` before reading back after a write.

### 6. `AddLonePoint` alone does not persist Smart Warp points

Calling `mesh:AddLonePoint(v, 0)` without a following `AppendPoint` leaves `CountPoints()` at `0`. To build a Smart Warp mesh, draw a closed perimeter curve (`AddLonePoint` + `AppendPoint` + `WeldPoints`) plus connected interior polyline(s), mark vertices `MOHO.PEAKED` with `fParent = -2`, then call `vl:SetContinuousTriangulation(true)`, `vl:MarkAsWarpLayer(true, moho.document)`, `vl:PauseContinuousTriangulation(false)`, and `vl:UpdateWarpLayer()`.

### 7. `MohoPhysicsOptions` animated channels

`po.fMotorSpeed` is an `AnimVal` (`:GetValue(frame)` / `:SetValue(frame, num)`) and `po.fForceVector` is an `AnimVec2` (`:GetValue(frame)` / `:SetValue(frame, LM.Vector2)`), not plain Lua numbers or raw `LM.Vector2` values.

### 8. `LayerComp` group-child membership

Adding only a parent `GroupLayer` or `BoneLayer` to a `LayerComp` hides its children when applying the comp or rendering with `-layercomp`. Recursively add descendant layers when a group is included.

### 9. Bone dynamics default state

Newly created bones have `fBoneDynamics:GetValue(0) == true` by default while per-axis toggles (`fAngleDynamics`, `fPosDynamics`, `fScaleDynamics`, `fWindDynamics`) default to `false`. Check both `fBoneDynamics` and at least one axis or wind toggle when testing whether dynamics are actually active.

### 10. Timeline markers sentinel key

`MohoDoc.fTimelineMarkers` and `MohoLayer.fTimelineMarkers` are `AnimString` channels containing a built-in sentinel key at frame `-1000000`. Skip negative sentinel frames when enumerating markers.

### 11. Headless `SS_glTFExport` and `SS_SVGImport`

Both scripts are loaded globally in Moho 14.4 (`SS_glTFExport`, `SS_SVGImport`) and hold their local dialog tables as Lua 5.4 upvalues accessible via `debug.getupvalue`. Temporarily stubbing `<Dialog>.new` to return a mock `DoModal()` and capturing `LM.GUI.Alert` allows headless glTF 2.0 export and Moho 14 SVG import without modal dialogs.

### 12. Custom tool icons

Moho Pro 14.4 loads three sibling 8-bit RGBA PNG files next to `Tool/<ScriptName>.lua`: `<ScriptName>.png` (`24x20`), `<ScriptName>@2x.png` (`48x40`), and `<ScriptName>_large.png` (`48x40`). Return `false` from `ColorizeIcon()` to keep full-color icons intact across UI themes.

### 13. Dispatch callback safety

Never invoke `server.poll()` (especially `FileNew`, `FileOpen`, `FileClose`, or `exportGltf`) or `moho.view:DrawMe()` inside `OnMouseMoved`, `IsEnabled`, or `UpdateWidgets`. Dispatch `server.poll(moho)` only from `DrawMe` (non-lifecycle RPCs) and `HandleMessage(MSG_POLL)` via a dedicated `"MCP Sync"` button on the Poller tool (all RPCs including document lifecycle).
