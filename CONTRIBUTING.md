# Contributing

Bug reports, macOS host testing, and focused pull requests are welcome.

## Development Setup

Requirements:

- Node.js 20 or newer (zero runtime npm dependencies in `src/`)
- Python 3.11 or newer (only for `scripts/check_hygiene.py`)
- Moho Pro 14.4 (required when testing Lua plugin changes live)

Run the offline checks before opening a PR:

```powershell
python scripts/check_hygiene.py
npm test
```

`check_hygiene.py` checks UTF-8/ASCII cleanliness, `node --check` on all `.mjs` files, Lua syntax balance, and 1:1 parity between `rpcMethod` entries in `src/tools/` and handler registrations in `moho-plugin/MohoStudioMCP_Server.lua`.

## Testing Lua Plugin Changes Live in Moho

1. Preview the plugin copy plan:
   ```powershell
   node src/server.mjs install
   ```
2. Install into Moho's Scripts folder (use an Administrator shell for `Program Files`, or pass `--moho-scripts-dir` for your Moho Custom Content Folder):
   ```powershell
   node src/server.mjs install --apply
   ```
3. In Moho Pro 14.4, reload scripts (`Ctrl+Shift+Alt+L`) and click `Scripts > MohoStudioMCP > Start/Stop MohoStudioMCP Server`.
4. Confirm file parity and plugin version:
   ```powershell
   node src/server.mjs doctor
   ```
5. Test new or modified handlers against a disposable document (`document_new` and `document_close` with `force: true`).

## Moho 14.4 Lua Guidelines

Read [docs/MOHO_14_4_LUA_API_VERIFIED.md](docs/MOHO_14_4_LUA_API_VERIFIED.md) and [AGENTS.md](AGENTS.md) before editing Lua handlers. Several Moho 14.4 `tolua++` bindings have non-obvious crash modes (such as `M_Style.fName`, `LayerComp:SetName` requiring `LM.String`, and calling `FileNew`/`FileClose` inside `DrawMe` or `IsEnabled`).

Please keep:

- Zero external npm runtime dependencies in `src/`
- ASCII-only text in `.mjs`, `.lua`, `.py`, `.json`, `.yml`, and `.txt` files
- Small, focused commits with clear test coverage for any protocol, IPC, or CLI changes
