import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { runDoctor, runInstall, cleanToolListText } from "../src/cli.mjs";
import { resolveMohoExecutable, buildMacCaptureArgs } from "../src/ipc.mjs";
import { getToolsForProfile, TOOLS } from "../src/tools.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.resolve(__dirname, "../src/server.mjs");

function run() {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "moho-studio-cli-test-"));
  const fakeScripts = path.join(tmpRoot, "MohoScripts");
  const fakeHome = path.join(tmpRoot, "Home");
  const fakeIpc = path.join(tmpRoot, "ipc");
  fs.mkdirSync(path.join(fakeScripts, "Tool"), { recursive: true });
  fs.mkdirSync(path.join(fakeHome, ".cursor"), { recursive: true });
  fs.mkdirSync(path.join(fakeHome, ".codex"), { recursive: true });

  const toolListPath = path.join(fakeScripts, "Tool", "_tool_list.txt");
  fs.writeFileSync(toolListPath, 'group MOHO.Localize("/Tools/Group/Draw=Draw")\ntool\tlm_select_points\tG\n', "utf8");

  const cursorCfg = path.join(fakeHome, ".cursor", "mcp.json");
  fs.writeFileSync(cursorCfg, JSON.stringify({ mcpServers: { existing: { command: "echo" } } }, null, 2), "utf8");

  const codexCfg = path.join(fakeHome, ".codex", "config.toml");
  fs.writeFileSync(codexCfg, 'model = "gpt-5"\n\n[mcp_servers.other]\ncommand = "node"\n', "utf8");

  try {
    // 1. Doctor before install -> not_installed
    const docBefore = runDoctor({ mohoScriptsDir: fakeScripts, ipcDir: fakeIpc, homeDir: fakeHome });
    assert.equal(docBefore.plugin.state, "not_installed");
    assert.equal(docBefore.ipc.running, false);
    assert.ok(docBefore.nextSteps.length > 0);

    // 2. Dry-run install does not modify files
    const dry = runInstall({
      apply: false,
      scope: "all",
      mohoScriptsDir: fakeScripts,
      ipcDir: fakeIpc,
      homeDir: fakeHome,
      clients: "cursor,codex",
      tools: "core",
      useNpx: true,
    });
    assert.equal(dry.mode, "dry_run");
    assert.equal(fs.existsSync(path.join(fakeScripts, "Menu", "MohoStudioMCP", "MohoStudioMCP_Server.lua")), false);

    // 3. Apply install writes plugin + updates _tool_list.txt + updates JSON/TOML configs with backups
    const applied = runInstall({
      apply: true,
      scope: "all",
      mohoScriptsDir: fakeScripts,
      ipcDir: fakeIpc,
      homeDir: fakeHome,
      clients: "cursor,codex",
      tools: "core",
      useNpx: true,
    });
    assert.equal(applied.status, "installed_and_verified");
    assert.equal(applied.backups.length, 3, "Expected backups for _tool_list.txt, mcp.json, config.toml");
    assert.ok(applied.plugin.verifiedFiles >= 18);

    const updatedToolList = fs.readFileSync(toolListPath, "utf8");
    assert.ok(updatedToolList.includes("MohoStudioMCP_Poller"));

    const updatedCursor = JSON.parse(fs.readFileSync(cursorCfg, "utf8"));
    assert.ok(updatedCursor.mcpServers.existing, "Unrelated Cursor MCP server must be preserved");
    assert.equal(updatedCursor.mcpServers.moho.command, "npx");
    assert.deepEqual(updatedCursor.mcpServers.moho.args, ["-y", "moho-studio-mcp"]);
    assert.equal(updatedCursor.mcpServers.moho.env.MOHO_STUDIO_TOOLS, "core");

    const updatedCodex = fs.readFileSync(codexCfg, "utf8");
    assert.ok(updatedCodex.includes('[mcp_servers.other]'), "Unrelated Codex section must be preserved");
    assert.ok(updatedCodex.includes('[mcp_servers.moho]'));
    assert.ok(updatedCodex.includes('MOHO_STUDIO_TOOLS = "core"'));

    // 4. Doctor after install + live status.json -> up_to_date & running
    fs.mkdirSync(fakeIpc, { recursive: true });
    fs.writeFileSync(
      path.join(fakeIpc, "status.json"),
      JSON.stringify({ running: true, version: "3.1.0", mohoVersion: "14.4", startedAt: "2026-01-01T00:00:00Z" }),
      "utf8"
    );
    const docAfter = runDoctor({ mohoScriptsDir: fakeScripts, ipcDir: fakeIpc, homeDir: fakeHome });
    assert.equal(docAfter.plugin.state, "up_to_date");
    assert.equal(docAfter.plugin.toolListRegistered, true);
    assert.equal(docAfter.ipc.running, true);
    assert.equal(docAfter.ipc.versionMatch, true);

    // 5. Doctor detects outdated file when plugin file differs
    fs.appendFileSync(path.join(fakeScripts, "Tool", "MohoStudioMCP_Poller.lua"), "\n-- modified\n");
    const docOutdated = runDoctor({ mohoScriptsDir: fakeScripts, ipcDir: fakeIpc, homeDir: fakeHome });
    assert.equal(docOutdated.plugin.state, "outdated");
    assert.ok(docOutdated.plugin.outdatedFiles.includes("Tool/MohoStudioMCP_Poller.lua"));

    // 6. Clean tool list removes legacy entries when requested
    const cleaned = cleanToolListText(
      'group MOHO.Localize("/Tools/Group/MohoMCP=MohoMCP")\ntool\tMohoMCP_Poller\t...\n',
      true
    );
    assert.ok(!cleaned.includes("MohoMCP_Poller"));
    assert.ok(cleaned.includes("MohoStudioMCP_Poller"));

    // 7. Cross-platform Moho executable & macOS capture helpers
    const macExe = resolveMohoExecutable({
      platform: "darwin",
      env: {},
      existsSync: (p) => p === "/Applications/Moho Pro 14.app/Contents/MacOS/Moho",
    });
    assert.equal(macExe.exists, true);
    assert.equal(macExe.path, "/Applications/Moho Pro 14.app/Contents/MacOS/Moho");

    const envExe = resolveMohoExecutable({
      platform: "win32",
      env: { MOHO_EXE_PATH: "/custom/Moho" },
      existsSync: () => true,
    });
    assert.equal(envExe.source, "MOHO_EXE_PATH");
    assert.equal(envExe.path, "/custom/Moho");

    assert.deepEqual(buildMacCaptureArgs(1234, "/tmp/out.png"), ["-l", "1234", "-x", "-o", "/tmp/out.png"]);

    // 8. Tool profiles sanity check
    assert.equal(getToolsForProfile("full").length, TOOLS.length);
    assert.equal(getToolsForProfile("core").length, 28);
    assert.ok(getToolsForProfile("rigging").some((t) => t.name === "rig_audit"));
    assert.ok(getToolsForProfile("rigging").some((t) => t.name === "bone_createSmartDial"));
    assert.ok(getToolsForProfile("animation").some((t) => t.name === "switch_importLipSync"));
    assert.ok(getToolsForProfile("animation").some((t) => t.name === "rig_getControls"));
    assert.ok(getToolsForProfile("vector").some((t) => t.name === "style_manage"));
    assert.equal(getToolsForProfile("unknown_profile").length, TOOLS.length);

    // 9. Subprocess CLI smoke tests (--version, doctor --json)
    const verOut = execFileSync(process.execPath, [serverPath, "--version"], { encoding: "utf8" }).trim();
    assert.equal(verOut, "moho-studio-mcp 3.1.0");

    const doctorOut = execFileSync(
      process.execPath,
      [serverPath, "doctor", "--json", "--moho-scripts-dir", fakeScripts, "--ipc-dir", fakeIpc],
      { encoding: "utf8" }
    );
    const parsedDoctor = JSON.parse(doctorOut);
    assert.equal(parsedDoctor.server.version, "3.1.0");
    assert.equal(parsedDoctor.plugin.state, "outdated");

    console.log("PASS test_cli_and_platform: CLI install/doctor/backups + macOS helpers + tool profiles OK");
  } finally {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
}

run();
