# Moho Studio MCP

MCP server and Moho Pro 14.4 Lua 5.4 plugin for controlling Moho live over stdio.

It lets an MCP client (Claude Desktop, Cursor, VS Code, Codex, Antigravity, or any JSON-RPC stdio client) inspect and edit open Moho projects: creating vector geometry, saved styles, brushes, bone rigs, Smart Warps, Curvers, Liquid Shapes, Vitruvian Bones, masking setups, 360-degree Smart Bone Actions, keyframes, Papagayo/Rhubarb lip-sync, Frame-by-Frame switch layers, Layer Comps, glTF 2.0 exports, rig audits, and headless CLI renders.

The server is written in Node.js ESM with zero npm runtime dependencies (`src/`), and the plugin is plain Lua 5.4 (`moho-plugin/`).

## Demo

Scene built, rigged, animated, and rendered live inside Moho Pro 14.4 by an MCP agent using this server (79 editable layers, Liquid Shapes, Vitruvian weapon swap, Smart Bone expressions, baked 2D rigid-body shard physics, FBF impact frames, 4 Layer Comps, headless `Moho.exe -r` CLI render, and a 2.5 MB `.glb` glTF 2.0 export).

| Rendered Output | Live Moho Pro 14.4 Project and Timeline |
| :---: | :---: |
| ![Slime Knight rendered output](https://github.com/SavasTanriverdi/moho-studio-mcp/releases/download/v3.0.0/slime_knight_readme.gif) | ![Live Moho Pro 14.4 viewport, rig, and timeline](https://github.com/SavasTanriverdi/moho-studio-mcp/releases/download/v3.0.0/moho_ide_live.png) |

Full 1080p 24fps render: [slime_knight_boss_fight_1080p.mp4](https://github.com/SavasTanriverdi/moho-studio-mcp/releases/download/v3.0.0/slime_knight_boss_fight_1080p.mp4)

## Requirements

- Windows 10 or Windows 11 (x64): live-verified with Moho Pro 14.4, Win32 background window wake, `PrintWindow` capture, and `Moho.exe -r` CLI rendering.
- macOS: experimental host support (`Moho.app` CLI render path discovery and `screencapture` window capture; not yet hardware-verified on macOS, and background poller auto-click is Windows-only).
- Moho Pro 14.4.
- Node.js 20 or newer.
- FFmpeg (optional, useful for encoding PNG sequences from `document_cliRender` into MP4 or GIF when system video codecs are unavailable).

## Quick Start (npx, No Python Required)

### 1. Install the Moho Lua plugin

Preview what the installer will copy (dry run is the default):

```powershell
npx moho-studio-mcp install
```

Install into Moho's `Program Files` Scripts folder (requires an Administrator PowerShell on Windows), or point `--moho-scripts-dir` at your Moho Custom Content Folder (`Preferences > General > Custom Content Folder`) to install without admin rights:

```powershell
# Option A: Moho Program Files (Administrator PowerShell)
npx moho-studio-mcp install --apply

# Option B: Moho Custom Content Folder (normal user)
npx moho-studio-mcp install --moho-scripts-dir "C:\Path\To\MohoContent\Scripts" --apply
```

The installer backs up `Tool/_tool_list.txt` before editing and verifies every copied `.lua` and icon `.png` file with SHA-256 checksums.

Start the plugin inside Moho Pro 14.4:

1. Reload scripts (`Ctrl+Shift+Alt+L`) or restart Moho.
2. Open `Scripts > MohoStudioMCP > Start/Stop MohoStudioMCP Server`.

Verify your setup at any time with:

```powershell
npx moho-studio-mcp doctor
```

### 2. Configure your MCP client

#### Claude Desktop, Cursor, VS Code, Antigravity, or any JSON MCP client

```json
{
  "mcpServers": {
    "moho": {
      "command": "npx",
      "args": ["-y", "moho-studio-mcp"]
    }
  }
}
```

#### Codex CLI (`~/.codex/config.toml`)

```toml
[mcp_servers.moho]
command = "npx"
args = ["-y", "moho-studio-mcp"]
startup_timeout_sec = 30
tool_timeout_sec = 60
```

You can also let the Node CLI patch existing client configs (`claude`, `cursor`, `antigravity`, `codex`) with automatic timestamped backups:

```powershell
npx moho-studio-mcp install --scope client --npx
npx moho-studio-mcp install --scope client --npx --apply
```

If you cloned the repository locally instead of using `npx`, point `command` to `node` and `args` to `["C:/path/to/moho-studio-mcp/src/server.mjs"]` (or pass `--local-node`). `scripts/install.py` remains available for Python workflows as well.

### Tool Profiles (Optional Context Budget Control)

By default the server exposes all 82 tools (`full`). If your MCP client has a tight context window, set `MOHO_STUDIO_TOOLS` or pass `--tools <profile>`:

| Profile | Tools | Intended Use |
| :--- | :---: | :--- |
| `full` (default) | 82 | Full Moho Pro 14.4 toolset |
| `core` | 28 | Status, document, layers, basic bones, `bone_createSmartDial`, `rig_getControls`, `rig_audit`, keyframes, basic shapes, `batch_execute` |
| `rigging` | 55 | Skeletons, Smart Bone Dials, constraints, dynamics, Vitruvian Bones, Smart Bones, Smart Warp, `rig_getControls`, `rig_audit` |
| `animation` | 56 | Puppet controls (`rig_getControls`), keyframes, cycles, retiming, tweening, lip-sync, FBF, particles, physics, camera, CLI render |
| `vector` | 38 | Vector shapes, points, topology, Smart Warp, Curver, Curve Profile, Liquid Shapes, Styles |

Example using the `core` profile:

```json
{
  "mcpServers": {
    "moho": {
      "command": "npx",
      "args": ["-y", "moho-studio-mcp", "--tools", "core"]
    }
  }
}
```

## How It Works

Moho runs an embedded Lua 5.4 interpreter with no built-in stdio server. Instead of polling a socket from a blocking loop, this bridge uses atomic temp-and-rename JSON files in `%TEMP%\moho-studio-mcp` (overridable via `MOHO_STUDIO_IPC_DIR`):

1. Each tool call writes `req_<pid>_<seq>_<hex>.json` and waits for `resp_<pid>_<seq>_<hex>.json`. Unique per-request IDs let multiple MCP clients talk to Moho without overwriting each other's files.
2. Inside Moho, the Lua plugin scans the IPC folder with Moho's native `moho:BeginFileListing()` instead of spawning `cmd.exe`, executes each handler inside `pcall`, and wraps mutations in `PrepUndo` / `UpdateUI`.
3. Normal edits run inside `DrawMe`. Document-lifecycle operations (`document_new`, `document_open`, `document_close`, `document_exportGltf`) are restricted to Moho's UI button handler (`HandleMessage`) via a dedicated `"MCP Sync"` button on the Poller tool, because switching or closing a document inside `DrawMe`, `IsEnabled`, or `UpdateWidgets` crashes Moho Pro 14.4.
4. On Windows, when Moho is idle or unfocused, `src/ipc.mjs` locates the Poller tool's teal-star icon using `PrintWindow` and clicks it via background `PostMessage` without moving the cursor or stealing focus.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for protocol details and [docs/MOHO_14_4_LUA_API_VERIFIED.md](docs/MOHO_14_4_LUA_API_VERIFIED.md) for the verified Moho 14.4 Lua API quirks behind the handlers.

## Tools, Resources, and Prompts

The server implements MCP `2025-03-26` (backward compatible with `2024-11-05`) and exposes 82 annotated tools (79 live Lua RPCs and 3 host tools), 2 resources, and 7 prompts.

Resources:

- `moho-studio://guide`: active profile status, short tool index, and workflow notes.
- `moho-studio://playbook`: 16 Moho Pro 14.4 rigging, studio control panel, character performance, shading, animation, and glTF rules for AI agents operating Moho.

Prompts:

- `animate_character_performance`: inspects an existing character via `rig_getControls`, then animates blinks, mouth/lip-sync, head/body Smart Bone Dials, walk cycles on Foot IK Targets, and arm arcs.
- `build_smart_bone_controls`: builds a side-mounted Smart Bone Dial panel (`Blink`, `Mouth Open`, `Head Turn`, `Body Turn`, `Eyebrows`) via `bone_createSmartDial`.
- `rig_character`: step-by-step Frame 0 rigging workflow ending with `rig_audit`.
- `create_360_turnaround`: exact +/-360-degree Smart Bone turnaround setup.
- `painterly_vector_shading`: Saved Styles, Moho 14 Brushes, Point Colors, and masked shading.
- `prepare_gltf_export`: `rig_audit`, `rig_auditGltf`, and headless `document_exportGltf`.
- `import_lipsync_animation`: Papagayo `.dat` / Rhubarb JSON lip-sync mapping onto a SwitchLayer.

| Category | Count | Tools |
| :--- | :---: | :--- |
| System and Live Lua | 4 | `moho_status`, `moho_activatePoller`, `moho_apiInspect`, `lua_execute` |
| Document, Render, glTF, Audit and Layer Comps | 20 | `document_getInfo`, `document_new`, `document_open`, `document_save`, `document_saveAs`, `document_close`, `document_undo`, `document_setSettings`, `document_import`, `document_setFrame`, `document_renderFrame`, `document_renderRange`, `document_captureWindow`, `document_cliRender`, `document_exportGltf`, `rig_auditGltf`, `rig_audit`, `rig_getControls`, `layercomp_list`, `layercomp_manage` |
| Layers, Masking, Switch, Lip-Sync, FBF and Particles | 21 | `layer_list`, `layer_getProperties`, `layer_create`, `layer_delete`, `layer_duplicate`, `layer_reparent`, `layer_select`, `layer_setProperties`, `layer_bindToBone`, `layer_setWarpLayer`, `layer_setMasking`, `layer_setLayerOrder`, `layer_convertType`, `layer_groupSelection`, `layer_followPath`, `layer_referenceManage`, `layer_renderImage`, `switch_setActive`, `switch_importLipSync`, `fbf_manage`, `particle_configure` |
| Bones, Smart Dials, Vitruvian, Wind and 2D Physics | 14 | `bone_list`, `bone_create`, `bone_createSmartDial`, `bone_delete`, `bone_setTransform`, `bone_setProperties`, `bone_setConstraints`, `bone_setDynamics`, `bone_mirror`, `bone_freezePose`, `bone_listGroups`, `bone_manageGroup`, `bone_setWind`, `physics_configure` |
| Animation, Actions, Markers and Camera | 13 | `animation_getKeyframes`, `animation_setKeyframes`, `animation_deleteKeyframe`, `animation_createCycle`, `animation_retime`, `animation_tween`, `timeline_markers`, `action_list`, `action_activate`, `action_createSmartBone`, `action_manage`, `camera_get`, `camera_setKeyframe` |
| Vector, Smart Warp, Curver, Liquid Shapes and Styles | 9 | `mesh_getData`, `mesh_createShape`, `mesh_editShape`, `mesh_editPoints`, `mesh_editTopology`, `mesh_createSmartWarp`, `mesh_setCurveProfile`, `mesh_liquidShapes`, `style_manage` |
| Batch | 1 | `batch_execute` |

Notable Moho 14.4 behaviors handled directly by the tools:

- `rig_getControls` summarizes an open character's complete puppet control surface (Smart Bone Dials with exact angle sweeps and limits, IK Targets, Pin Bones, SwitchLayers, Vitruvian groups, and Regular Actions) so an agent animates characters through studio controls rather than raw vertices.
- `bone_createSmartDial` builds a labeled, zero-strength, angle-constrained side Smart Bone Dial (single or bidirectional `<Dial>` + `<Dial 2>` 96-frame linear Actions) in a single call.
- `rig_audit` checks rigs for non-zero strength on Pin Bones / IK Targets / Smart Bone dials, rigid-bound GroupLayers trapping bone-bound children, Animated Layer Order collisions across multiple Smart Bones, BoneLayers left inside an active Action, unbound artwork, and missing pre-roll for active dynamics or particles.
- `switch_importLipSync` parses Papagayo `.dat` (`MohoSwitch1`), Rhubarb Lip Sync JSON (`mouthCues`), or explicit cues with optional Preston Blair preset mapping (`rhubarb_to_preston_blair`), custom `phonemeMap`, fallback child, and missing-child diagnostics.
- `.svg` files passed to `document_import` are routed headlessly through Moho 14's bundled `SS_SVGImport` script rather than the older `FileImport` path.
- `document_exportGltf` drives Moho 14's bundled `SS_glTFExport` headlessly without opening a modal dialog; `rig_auditGltf` checks for point-animated vectors missing a Warp Layer, active bone dynamics, non-in-place Actions, and `gltf_*` tags beforehand.
- `action_createSmartBone` with `mode: "360"` sets an unwrapped `zeroAngle +/- 2*pi` sweep (96 frames, linear bone keys, optional Frame 0 to end-frame mirroring) and restores Mainline when finished.
- `document_close` with `force: true` saves dirty untitled documents to a temporary file before calling `moho:FileClose()` and deletes the temp file afterward so Moho never blocks on a native Save prompt.
- `batch_execute` wraps multiple operations into a single Undo entry and one coalesced `UpdateUI()` pass.

## Known Limitations and Security Notes

- Windows 10/11 x64 is the primary live-verified platform. On macOS, `document_cliRender` and `document_captureWindow` are implemented using standard macOS paths and `screencapture`, but background poller auto-click (`moho_activatePoller`) is Windows-only, so macOS users should keep the Poller tool selected or click `"MCP Sync"` for document-lifecycle calls.
- `document_cliRender` calls `Moho.exe -r` (or `Moho -r` on macOS) in a background process. Direct `MP4` and `MOV` output depends on installed OS codecs; rendering a `PNG` sequence and encoding with `ffmpeg` works consistently across machines.
- `lua_execute` evaluates arbitrary Lua 5.4 inside the Moho process (`ScriptInterface`). This server only listens on local stdio and reads local temp files; keep it bound to trusted local sessions and do not expose it over a network tunnel.
- Viewport screenshots (`document_captureWindow`) do not always show final Masks, Layer Outlines, Point Colors, Merged-Alpha brushes, Soft Edge, or unsolved mid-timeline Bone Dynamics. Use `document_renderFrame` or `document_cliRender` when checking visual output.

## Repository Layout

- `src/`: Node.js stdio MCP server (`server.mjs`), JSON Schemas + annotations + tool profiles (`tools.mjs`), setup CLI and doctor (`cli.mjs`), MCP prompts (`prompts.mjs`), IPC client + host helpers (`ipc.mjs`), runtime config (`config.mjs`), and `moho-studio://playbook` (`playbook.mjs`).
- `moho-plugin/`: Moho Pro 14.4 Menu script, Poller tool, toolbar icons (`24x20` and `48x40`), Lua JSON codec, Bowyer-Watson Delaunay triangulator, and modular tool handlers.
- `scripts/`: Legacy Python installer (`install.py`), offline hygiene and 1:1 RPC parity checker (`check_hygiene.py`), and SDF icon generator (`generate_icons.py`).
- `tests/`: MCP stdio protocol tests (`test_mcp_protocol.mjs`), concurrent dual-client mock IPC tests (`test_ipc_mock.mjs`), and Node CLI / platform / profile tests (`test_cli_and_platform.mjs`).
- `docs/`: Architecture notes ([ARCHITECTURE.md](docs/ARCHITECTURE.md)) and verified Moho Pro 14.4 Lua API reference ([MOHO_14_4_LUA_API_VERIFIED.md](docs/MOHO_14_4_LUA_API_VERIFIED.md)).
- `llms.txt`: Compact index for AI coding assistants and crawlers.

## Testing

```powershell
python scripts/check_hygiene.py
npm test
```

`check_hygiene.py` verifies UTF-8/ASCII cleanliness, `node --check` on every `.mjs` file, Lua syntax balance, and 1:1 parity between `rpcMethod` entries in `src/tools.mjs` and handlers registered in `moho-plugin/MohoStudioMCP_Server.lua`.

## License

MIT. See [LICENSE](LICENSE).

Directory listing: [Glama MCP Server Directory](https://glama.ai/mcp/servers/SavasTanriverdi/moho-studio-mcp).
