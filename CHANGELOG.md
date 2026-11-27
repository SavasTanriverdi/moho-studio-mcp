# Changelog

All notable changes to `moho-studio-mcp` are documented in this file.

## [Unreleased]

### Changed
- Split `src/tools.mjs` into domain schema modules under `src/tools/` (`shared.mjs`, `system.mjs`, `document.mjs`, `layers.mjs`, `bones.mjs`, `animation.mjs`, `mesh.mjs`, `batch.mjs`) and extended `scripts/check_hygiene.py` to detect duplicate RPC declarations.
- Hardened IPC response reads in `src/ipc.mjs` so transient empty or partial reads retry before unlinking the response file, replaced bare catch blocks with explicit cleanup helpers, and pruned stale `.keepalive_*.ps1` files older than one hour.
- Added strict `--tools` profile validation and subcommand `--help` support in `src/cli.mjs`.

### Added
- Published MCP `instructions` on `initialize`, `resources/templates/list` support, and `EPIPE` handling on `process.stdout` in `src/server.mjs`.
- Added `CHANGELOG.md`, `CONTRIBUTING.md`, and structured GitHub bug report templates.

## [3.1.0] - 2026-11-27

### Added
- `rig_getControls` (`rig.getControls`): read-only Puppet Control Surface inspector returning Smart Bone Dials (with action angle sweeps and constraints), IK targets, Pin Bones, Switch layers, Vitruvian Bone groups, and Regular Actions.
- `bone_createSmartDial` (`bone.createSmartDial`): single-call Smart Bone Dial builder creating zero-strength, labeled, color-tagged, IK-ignored, angle-constrained side dials with 96-frame single or bidirectional (`<Dial>` and `<Dial 2>`) Smart Bone Actions.
- `rig_audit` (`rig.audit`): read-only Rig Health Linter checking non-zero control-bone strength, rigid-bound groups trapping children, Animated Layer Order collisions across multiple Smart Bones, active-action leaks, unbound artwork, and dynamics/particle pre-roll.
- `switch_importLipSync` (`switch.importLipSync`): imports Papagayo `.dat` (`MohoSwitch1`), Rhubarb Lip Sync JSON (`mouthCues`), or explicit cues onto a SwitchLayer with `rhubarb_to_preston_blair` mapping, custom `phonemeMap`, fallback child, and missing-child diagnostics.
- Pure Node.js CLI (`src/cli.mjs`): `npx moho-studio-mcp install [--apply]` and `npx moho-studio-mcp doctor [--json]` with timestamped backups and SHA-256 verification.
- MCP `2025-03-26` negotiation (compatible with `2024-11-05`), tool `annotations` and full parameter descriptions across all 82 tools, 7 built-in MCP prompts (`src/prompts.mjs`), Rule 16 in `moho-studio://playbook`, and tool profiles (`MOHO_STUDIO_TOOLS=full|core|rigging|animation|vector`).
- Experimental macOS host support in `src/ipc.mjs` for `Moho.app` CLI rendering and `screencapture` window capture.

### Fixed
- Flushed `process.stdout` cleanly on `stdin` EOF in `src/server.mjs` to prevent truncated `tools/list` output on Linux pipes.
- Fixed 2-argument Bezier handle cloning in `moho-plugin/moho_studio/tools/animation.lua`.
- Updated GitHub Actions CI workflow to `@v7` actions (`checkout`, `setup-node`, `setup-python`).

## [3.0.0] - 2026-11-24

### Added
- Initial public release with 78 MCP tools (75 live Moho Pro 14.4 Lua 5.4 RPCs and 3 Windows host tools) and 2 MCP resources (`moho-studio://guide` and `moho-studio://playbook`).
- Atomic temp-and-rename JSON IPC with per-request IDs, crash-safe `DrawMe` vs `HandleMessage` (`"MCP Sync"`) dispatch, and `batch_execute` single-step Undo coalescing.
- Headless wrappers for Moho 14.4 `SS_glTFExport` and `SS_SVGImport`, plus `document_cliRender` (`Moho.exe -r`) and `rig_auditGltf`.
