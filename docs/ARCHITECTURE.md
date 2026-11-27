# Architecture

## Process Topology

```text
MCP Client (Claude Desktop / Cursor / VS Code / Codex / Antigravity)
   |  stdio (JSON-RPC 2.0, newline-delimited MCP 2025-03-26 / 2024-11-05)
   v
src/server.mjs  (Node.js 20+ ESM, zero npm deps; also dispatches install/doctor CLI)
   |-- Tool Profiles: MOHO_STUDIO_TOOLS=full|core|rigging|animation|vector
   |-- MCP Resources (2):
   |     moho-studio://guide     active profile, tool index, and workflow notes
   |     moho-studio://playbook  16 Moho Pro 14.4 authoring and performance rules
   |-- MCP Prompts (7):
   |     animate_character_performance, build_smart_bone_controls, rig_character,
   |     create_360_turnaround, painterly_vector_shading, prepare_gltf_export,
   |     import_lipsync_animation
   |
   |-- Host Native Tools (3):
   |     moho_activatePoller     Win32 PrintWindow icon match + PostMessage click
   |     document_captureWindow  Win32 EnumWindows/PrintWindow (macOS screencapture)
   |     document_cliRender      Moho -r headless GPU batch renderer (Windows + macOS)
   |
   |-- Atomic File IPC in %TEMP%\moho-studio-mcp\ (or MOHO_STUDIO_IPC_DIR):
   |     req_<pid>_<seq>_<hex>.json  ->  resp_<pid>_<seq>_<hex>.json
   v
moho-plugin/MohoStudioMCP_Server.lua  (Moho Pro 14.4 Lua 5.4 runtime)
   |-- DrawMe hooks on Moho tools + Poller (normal RPCs)
   |-- HandleMessage(MSG_POLL) via Poller "MCP Sync" button (all RPCs + doc lifecycle)
   |-- moho:BeginFileListing(ipcDir) + LM.CreateDir (no cmd.exe spawns)
   |-- Re-entrancy guarded server.poll + pcall + coalesced batch Undo/UpdateUI
   |-- Headless wrappers for bundled Moho 14 scripts (SS_glTFExport, SS_SVGImport)
   v
Moho Pro 14.4 Engine (ScriptInterface `moho`)
```

## Crash-Safe Dispatch

Moho Pro 14.4 holds live C++ document and view pointers on the call stack during `WM_PAINT` (`DrawMe`), toolbar refresh sweeps (`IsEnabled`, `UpdateWidgets`), and pointer move callbacks (`OnMouseMoved`). Opening, switching, or closing a document inside those callbacks triggers a fatal user-callback exception in Moho.

To avoid that failure mode:

1. `server.poll(moho, source)` is called only from `DrawMe` (`source = "draw"`) and `HandleMessage(MSG_POLL)` (`source = "command"`). It is never called from `IsEnabled`, `UpdateWidgets`, or `OnMouseMoved`.
2. Four document-lifecycle and export methods (`DOC_LIFECYCLE_METHODS`) are restricted to `"command"` dispatch:
   - `document.new`
   - `document.open`
   - `document.close`
   - `document.exportGltf`
   Any `batch.execute` request containing one of those methods is also deferred until `"command"` dispatch.
3. On Windows, for normal RPCs `src/ipc.mjs` nudges Moho's main window with Win32 `RedrawWindow` / `WM_MOUSEMOVE`. If a request stalls past `450ms` (or immediately at `50ms` for `DOC_LIFECYCLE_METHODS`), `src/ipc.mjs` runs `activatePoller()`. That helper captures the window via `PrintWindow`, locates the Poller tool's unique teal-star icon, and sends background `PostMessage(WM_LBUTTONDOWN/UP)` clicks to select the Poller (if inactive) and press its `"MCP Sync"` `LM.GUI.Button`. That executes `HandleMessage(MSG_POLL)` on Moho's normal button-command stack without moving the cursor or taking focus.

## IPC Lifecycle

1. When the server starts in Moho, `server.lua` writes `status.json` (`running`, `version`, `mohoVersion`, `ipcDir`, `startedAt`) and clears stale `req_*.json` and `resp_*.json` files.
2. For each live RPC, `src/ipc.mjs` generates a unique ID `r_<pid>_<seq>_<hex>`, writes `req_<id>.json.tmp`, and atomically renames it to `req_<id>.json`.
3. `server.poll(moho, source)` lists `ipcDir` using `moho:BeginFileListing(ipcDir)`, claims up to 8 eligible `req_*.json` files per tick, deletes each request file before running the handler inside `pcall`, and atomically writes `resp_<id>.json`.
4. `src/ipc.mjs` checks for `resp_<id>.json` every `35ms`, deletes it after reading, and returns JSON text (plus inline base64 PNG image content for `document_renderFrame`, `layer_renderImage`, `document_captureWindow`, and `document_cliRender`).

## Tool Groups (82 Total)

| Domain | Tools | Notes |
| :--- | :---: | :--- |
| System and Live Lua | 4 | `moho_status`, `moho_activatePoller` (host), `moho_apiInspect`, `lua_execute` |
| Document, Render, glTF, Audit and Layer Comps | 20 | Includes host `document_captureWindow` and `document_cliRender`, headless `SS_SVGImport` and `SS_glTFExport` wrappers, `rig_auditGltf`, `rig_audit`, and `rig_getControls` |
| Layers, Masking, Switch, Lip-Sync, FBF and Particles | 21 | Layer tree, binding, masking, animated layer order, type conversion, follow path, reference sync, `switch_importLipSync`, FBF, particles |
| Bones, Smart Dials, Vitruvian, Wind and 2D Physics | 14 | Geometry-snapped bones, pin bones, `bone_createSmartDial`, constraints, 3-axis dynamics, mirroring, freeze pose, Vitruvian groups, wind, physics |
| Animation, Actions, Markers and Camera | 13 | 48 channels, Separate Dimensions, Bezier handles, range cycles, retiming, tweening, markers, 360 Smart Bones, camera |
| Vector, Smart Warp, Curver, Liquid Shapes and Styles | 9 | Shape/point/topology editing, Delaunay/Quad/Curver warps, curve profile, Liquid Shapes, Saved Styles and Brushes |
| Batch | 1 | `batch_execute` |

## Undo, Coalescing, CLI Installer and Backups

Every mutating Lua handler calls `helpers.prepUndo(moho, layer, multi)` before writing and `helpers.updateUI(moho)` after. Inside `batch_execute`, `helpers.batchDepth` suppresses per-operation undo snapshots and intermediate redraws so the whole batch lands as a single Undo step with one `UpdateUI()` pass.

Both `src/cli.mjs` (`npx moho-studio-mcp install`) and `scripts/install.py` default to dry-run mode. When run with `--apply`, they write `.moho_studio_backup_<YYYYMMDD_HHMMSS>` beside any modified client config or `_tool_list.txt` file and verify copied Lua and icon files byte-for-byte afterward. `npx moho-studio-mcp doctor` checks Node runtime, Moho executable path, installed plugin SHA-256 parity, and live IPC `status.json` version alignment.

Moho Pro 14.4 Lua 5.4 API signatures and engine edge cases are documented in [MOHO_14_4_LUA_API_VERIFIED.md](MOHO_14_4_LUA_API_VERIFIED.md).
