# Moho Studio MCP - Engineering Rules

This repository (`moho-studio-mcp`) contains a zero-dependency Node.js stdio MCP server (`src/`) and a Moho Pro 14.4 Lua 5.4 plugin (`moho-plugin/`) for live 2D animation authoring, rigging, shading, glTF 2.0 export, and headless CLI rendering on Windows.

## 1. Code hygiene

- Keep code, comments, identifiers, filenames, tests, docs, and commit messages in English and UTF-8.
- Use ASCII-only filenames (`[A-Za-z0-9_.-]`).
- Keep `.py`, `.mjs`, `.lua`, `.json`, `.yml`, and `.txt` files strictly ASCII with no emojis.
- Keep zero external npm runtime dependencies in `src/`. Target Node.js 20+ native ESM.
- Maintain exact 1:1 parity between `rpcMethod` declarations in `src/tools.mjs` and handler registrations in `moho-plugin/MohoStudioMCP_Server.lua` (enforced by `scripts/check_hygiene.py`).

## 2. Moho Pro 14.4 Lua 5.4 invariants

Do not guess Moho Lua API signatures. Verify them against Moho 14.4's bundled scripts (`C:\Program Files\Moho 14\Resources\Support\Scripts\`) and live runtime introspection (`moho_apiInspect` / `lua_execute`). See `docs/MOHO_14_4_LUA_API_VERIFIED.md` for full details.

Key invariants:

- Layer bone binding uses `layer:SetLayerParentBone(boneId)` (not `SetParentBone`).
- Bone parent assignment must set both `bone.fParent = parentId` and `bone.fAnimParent:SetValue(0, parentId)`.
- Bone dynamics use Moho 14's split channels: `bone.fBoneDynamics:SetValue(0, bool)`, `bone.fAngleDynamics`, `bone.fPosDynamics`, `bone.fScaleDynamics`, `bone.fWindDynamics`, `bone.fAngleTorqueForce`, `bone.fAngleSpringForce`, `bone.fAngleDampingForce`, and their `fPos*` / `fScale*` counterparts.
- IK targets use `bone.fTargetBone:SetValue(frame, targetId)`.
- Wrap live mutations in `helpers.prepUndo(moho, layer, multi)` and execute every RPC handler inside `pcall(...)` so Lua errors never crash Moho.
- Use `moho:BeginFileListing(dir)` and `moho:GetNextFile()` to scan directories instead of spawning `cmd.exe`.
- After bone or mesh mutations, call `skel:UpdateBoneMatrix(id)` and `helpers.updateUI(moho)` so subsequent queries see fresh matrices.
- Before calling `moho:FileRender(outPath)` for a specific frame, advance `moho:SetCurFrame(frame)` and `moho:UpdateUI()`, then restore the original frame if requested.
- Read and write `M_Style` names only via `style:Name()` and `style:SetName(name)`, guarded by `tolua.cast(st, "M_Style")`. Never access `style.fName`; it shares offset `+0x0` with `M_Style` and corrupts `tolua_ubox` into `LM_String`.
- Pass an `LM.String` userdata to `LayerComp:SetName` (`local s = LM.String:new_local(); s:Set(name); comp:SetName(s)`), never a plain Lua string. Passing a Lua string passes `NULL` and crashes Moho.
- Cast channels returned by `AnimChannel:ActionByName(name)` with `moho:ChannelAsAnimVal(ch)` or `moho:ChannelAsAnimVec3(ch)` before calling `:GetValue()`.
- Pass component index (`0` = scalar/X, `1` = Y, `2` = Z) as arg #1 to `InterpSetting` Bezier methods (`BezierInAngle`, `SetBezierInAngle`, and `InPercentage`/`OutAngle`/`OutPercentage` counterparts).
- Never call `moho:FileClose()` on a dirty untitled document without clearing dirty state first (save to a disposable temp `.moho` file, close, then `os.remove` the temp file) or Moho will block on a native Save prompt.

## 3. Crash-safe dispatch and IPC rules

- Invoke `server.poll(moho, source)` only from `DrawMe` (`"draw"`) and `HandleMessage(MSG_POLL)` (`"command"`). Never poll from `IsEnabled`, `UpdateWidgets`, or `OnMouseMoved`.
- Keep document-lifecycle methods (`document.new`, `document.open`, `document.close`, `document.exportGltf`) restricted to `"command"` dispatch in both `moho-plugin/moho_studio/server.lua` and `src/ipc.mjs`.
- Default IPC directory is `%TEMP%\moho-studio-mcp` (overridable via `MOHO_STUDIO_IPC_DIR`). Write request and response JSON files atomically using `.tmp` + rename with unique per-request IDs.
- Always run `scripts/install.py` in dry-run mode before `--apply`. Any external config edit (`config.toml`, `mcp_config.json`, `_tool_list.txt`) must write a timestamped backup and verify readback.
- Never bypass Windows UAC. Installing into `C:\Program Files\Moho 14\Resources\Support\Scripts` requires an elevated terminal, or a Moho Custom Content Folder passed via `--moho-scripts-dir`.

## 4. Verification gate

Before finishing any change:

1. Run `python scripts/check_hygiene.py`.
2. Run `npm test` (`tests/test_mcp_protocol.mjs` and `tests/test_ipc_mock.mjs`).
3. If Lua plugin files changed, deploy them to Moho, reload scripts (`Ctrl+Shift+Alt+L`), start `MohoStudioMCP Server`, and test against a disposable `document_new` scene before calling live behavior verified.
