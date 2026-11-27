// Pure Node.js ESM setup CLI and diagnostics for Moho Studio MCP v3.1.0 (zero external dependencies).

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { getIpcDir, resolveToolProfile, SERVER_INFO, TOOL_PROFILES } from "./config.mjs";
import { resolveMohoExecutable } from "./ipc.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const PACKAGE_ROOT = path.resolve(__dirname, "..");

const ICON_FILES = [
  "MohoStudioMCP_Poller.png",
  "MohoStudioMCP_Poller@2x.png",
  "MohoStudioMCP_Poller_large.png",
];

function sha256File(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function makeTimestamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

export function getDefaultMohoScriptsCandidates(platform = process.platform, homeDir = os.homedir()) {
  if (platform === "win32") {
    return [
      "C:\\Program Files\\Moho 14\\Resources\\Support\\Scripts",
      "C:\\Program Files\\Moho\\Resources\\Support\\Scripts",
      path.join(homeDir, "Documents", "Moho Pro", "Scripts"),
    ];
  }
  if (platform === "darwin") {
    return [
      "/Applications/Moho.app/Contents/Resources/Support/Scripts",
      "/Applications/Moho Pro 14.app/Contents/Resources/Support/Scripts",
      "/Applications/Moho 14.app/Contents/Resources/Support/Scripts",
      path.join(homeDir, "Documents", "Moho Pro", "Scripts"),
    ];
  }
  return [path.join(homeDir, "Moho Pro", "Scripts")];
}

export function resolveMohoScriptsDir({ cliDir, platform = process.platform, homeDir = os.homedir(), existsSync = fs.existsSync } = {}) {
  if (cliDir && String(cliDir).trim().length > 0) {
    const resolved = path.resolve(String(cliDir).trim());
    return { path: resolved, exists: existsSync(resolved), source: "cli", candidates: [resolved] };
  }
  const candidates = getDefaultMohoScriptsCandidates(platform, homeDir);
  for (const cand of candidates) {
    if (existsSync(cand)) {
      return { path: cand, exists: true, source: "auto", candidates };
    }
  }
  return { path: candidates[0], exists: false, source: "default", candidates };
}

function listLuaFilesRecursive(dir, baseDir = dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listLuaFilesRecursive(full, baseDir));
    } else if (entry.isFile() && entry.name.endsWith(".lua")) {
      out.push(path.relative(baseDir, full));
    }
  }
  return out.sort();
}

export function buildPluginFilePairs(scriptsDir, pkgRoot = PACKAGE_ROOT) {
  const pluginSrc = path.join(pkgRoot, "moho-plugin");
  const menuDest = path.join(scriptsDir, "Menu", "MohoStudioMCP");
  const toolDir = path.join(scriptsDir, "Tool");
  const pairs = [
    {
      label: "Menu/MohoStudioMCP/MohoStudioMCP_Server.lua",
      src: path.join(pluginSrc, "MohoStudioMCP_Server.lua"),
      dst: path.join(menuDest, "MohoStudioMCP_Server.lua"),
    },
    {
      label: "Tool/MohoStudioMCP_Poller.lua",
      src: path.join(pluginSrc, "MohoStudioMCP_Poller.lua"),
      dst: path.join(toolDir, "MohoStudioMCP_Poller.lua"),
    },
  ];
  for (const icon of ICON_FILES) {
    const src = path.join(pluginSrc, icon);
    if (fs.existsSync(src)) {
      pairs.push({
        label: `Tool/${icon}`,
        src,
        dst: path.join(toolDir, icon),
      });
    }
  }
  const libSrc = path.join(pluginSrc, "moho_studio");
  for (const rel of listLuaFilesRecursive(libSrc)) {
    pairs.push({
      label: `Menu/MohoStudioMCP/moho_studio/${rel.replace(/\\/g, "/")}`,
      src: path.join(libSrc, rel),
      dst: path.join(menuDest, "moho_studio", rel),
    });
  }
  return pairs;
}

export function cleanToolListText(text, removeLegacy = false) {
  const lines = String(text || "").replace(/^\uFEFF/, "").replace(/\r\n/g, "\n").split("\n");
  const out = [];
  for (const line of lines) {
    if (removeLegacy && (line.includes("/Tools/Group/MohoMCP=") || line.includes("MohoMCP_Poller"))) {
      continue;
    }
    if (line.includes("/Tools/Group/MohoStudioMCP=") || line.includes("MohoStudioMCP_Poller")) {
      continue;
    }
    out.push(line);
  }
  while (out.length > 0 && out[out.length - 1].trim() === "") {
    out.pop();
  }
  out.push("");
  out.push('group MOHO.Localize("/Tools/Group/MohoStudioMCP=MohoStudioMCP")');
  out.push("tool\tMohoStudioMCP_Poller\t...");
  return out.join("\n") + "\n";
}

function getClientConfigPaths(platform = process.platform, homeDir = os.homedir(), env = process.env) {
  let claudePath;
  if (platform === "win32") {
    const appData = env.APPDATA || path.join(homeDir, "AppData", "Roaming");
    claudePath = path.join(appData, "Claude", "claude_desktop_config.json");
  } else if (platform === "darwin") {
    claudePath = path.join(homeDir, "Library", "Application Support", "Claude", "claude_desktop_config.json");
  } else {
    claudePath = path.join(homeDir, ".config", "Claude", "claude_desktop_config.json");
  }
  return {
    claude: { kind: "json", path: claudePath },
    cursor: { kind: "json", path: path.join(homeDir, ".cursor", "mcp.json") },
    antigravity: { kind: "json", path: path.join(homeDir, ".gemini", "config", "mcp_config.json") },
    codex: { kind: "toml", path: path.join(homeDir, ".codex", "config.toml") },
  };
}

function stripTomlMohoSections(text) {
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/);
  const out = [];
  let skipping = false;
  for (const line of lines) {
    const m = line.match(/^\s*\[([^\]]+)\]\s*$/);
    if (m) {
      const sec = m[1].trim();
      if (sec === "mcp_servers.moho" || sec.startsWith("mcp_servers.moho.")) {
        skipping = true;
        continue;
      }
      skipping = false;
    }
    if (!skipping) {
      out.push(line);
    }
  }
  return out.join("\n").trimEnd();
}

function isNpxCacheDir(dir) {
  const norm = dir.replace(/\\/g, "/").toLowerCase();
  return norm.includes("/_npx/") || norm.includes("/npm-cache/_npx/");
}

function buildClientServerSpec({ useNpx, ipcDir, toolProfile, pkgRoot = PACKAGE_ROOT }) {
  const env = {};
  if (ipcDir) env.MOHO_STUDIO_IPC_DIR = ipcDir;
  if (toolProfile && toolProfile !== "full") env.MOHO_STUDIO_TOOLS = toolProfile;

  if (useNpx) {
    return {
      command: "npx",
      args: ["-y", "moho-studio-mcp"],
      env,
    };
  }
  return {
    command: process.execPath,
    args: [path.join(pkgRoot, "src", "server.mjs")],
    env,
  };
}

function parseCliFlags(argv) {
  const opts = {
    apply: false,
    json: false,
    removeLegacy: false,
    useNpx: null,
    scope: "plugin",
    clients: "auto",
    mohoScriptsDir: null,
    ipcDir: null,
    tools: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === "--apply") opts.apply = true;
    else if (tok === "--json") opts.json = true;
    else if (tok === "--remove-legacy") opts.removeLegacy = true;
    else if (tok === "--npx") opts.useNpx = true;
    else if (tok === "--local-node") opts.useNpx = false;
    else if (tok === "--scope" && i + 1 < argv.length) opts.scope = argv[++i];
    else if (tok.startsWith("--scope=")) opts.scope = tok.slice("--scope=".length);
    else if (tok === "--clients" && i + 1 < argv.length) opts.clients = argv[++i];
    else if (tok.startsWith("--clients=")) opts.clients = tok.slice("--clients=".length);
    else if (tok === "--moho-scripts-dir" && i + 1 < argv.length) opts.mohoScriptsDir = argv[++i];
    else if (tok.startsWith("--moho-scripts-dir=")) opts.mohoScriptsDir = tok.slice("--moho-scripts-dir=".length);
    else if (tok === "--ipc-dir" && i + 1 < argv.length) opts.ipcDir = argv[++i];
    else if (tok.startsWith("--ipc-dir=")) opts.ipcDir = tok.slice("--ipc-dir=".length);
    else if (tok === "--tools" && i + 1 < argv.length) opts.tools = argv[++i];
    else if (tok.startsWith("--tools=")) opts.tools = tok.slice("--tools=".length);
  }
  return opts;
}

export function runDoctor(options = {}) {
  const platform = options.platform || process.platform;
  const homeDir = options.homeDir || os.homedir();
  const ipcDir = options.ipcDir ? path.resolve(options.ipcDir) : getIpcDir();
  const pkgRoot = options.pkgRoot || PACKAGE_ROOT;

  const nodeMajor = Number(process.versions.node.split(".")[0]) || 0;
  const exeInfo = resolveMohoExecutable({ platform });
  const scriptsInfo = resolveMohoScriptsDir({ cliDir: options.mohoScriptsDir, platform, homeDir });

  const pairs = buildPluginFilePairs(scriptsInfo.path, pkgRoot);
  const missingFiles = [];
  const outdatedFiles = [];
  let matchedCount = 0;

  for (const p of pairs) {
    if (!fs.existsSync(p.dst)) {
      missingFiles.push(p.label);
    } else if (sha256File(p.src) !== sha256File(p.dst)) {
      outdatedFiles.push(p.label);
    } else {
      matchedCount += 1;
    }
  }

  const toolListPath = path.join(scriptsInfo.path, "Tool", "_tool_list.txt");
  let toolListRegistered = null;
  if (fs.existsSync(toolListPath)) {
    const txt = fs.readFileSync(toolListPath, "utf8");
    toolListRegistered = txt.includes("MohoStudioMCP_Poller");
  }

  let pluginState = "not_installed";
  if (missingFiles.length === 0 && outdatedFiles.length === 0 && toolListRegistered !== false) {
    pluginState = "up_to_date";
  } else if (matchedCount > 0 || outdatedFiles.length > 0) {
    pluginState = "outdated";
  }

  const statusPath = path.join(ipcDir, "status.json");
  let ipcStatus = null;
  if (fs.existsSync(statusPath)) {
    try {
      ipcStatus = JSON.parse(fs.readFileSync(statusPath, "utf8"));
    } catch {
      ipcStatus = { running: false, parseError: true };
    }
  }

  const running = Boolean(ipcStatus && ipcStatus.running === true);
  const versionMatch = running ? ipcStatus.version === SERVER_INFO.version : null;

  const clientConfigs = getClientConfigPaths(platform, homeDir);
  const detectedClients = {};
  for (const [name, cfg] of Object.entries(clientConfigs)) {
    detectedClients[name] = {
      path: cfg.path,
      exists: fs.existsSync(cfg.path),
    };
  }

  const nextSteps = [];
  if (pluginState !== "up_to_date") {
    const dirArg = options.mohoScriptsDir ? ` --moho-scripts-dir "${scriptsInfo.path}"` : "";
    nextSteps.push(`Run 'npx moho-studio-mcp install --apply${dirArg}' (elevated shell for Program Files, or pass your Moho Custom Content Scripts folder).`);
    nextSteps.push("In Moho Pro 14.4, reload scripts (Ctrl+Shift+Alt+L) and run Scripts > MohoStudioMCP > Start/Stop MohoStudioMCP Server.");
  } else if (!running) {
    nextSteps.push("Open Moho Pro 14.4 and click Scripts > MohoStudioMCP > Start/Stop MohoStudioMCP Server.");
  } else if (versionMatch === false) {
    nextSteps.push(`Live Moho plugin reports v${ipcStatus.version} while server is v${SERVER_INFO.version}; press Ctrl+Shift+Alt+L in Moho and restart MohoStudioMCP Server.`);
  }

  return {
    server: SERVER_INFO,
    node: { version: process.version, supported: nodeMajor >= 20 },
    platform: {
      os: platform,
      supportTier: platform === "win32" ? "verified" : platform === "darwin" ? "experimental" : "host_only",
    },
    mohoExecutable: exeInfo,
    plugin: {
      scriptsDir: scriptsInfo.path,
      scriptsDirExists: scriptsInfo.exists,
      state: pluginState,
      totalBundledFiles: pairs.length,
      matchedFiles: matchedCount,
      missingFiles,
      outdatedFiles,
      toolListPath: fs.existsSync(toolListPath) ? toolListPath : null,
      toolListRegistered,
    },
    ipc: {
      dir: ipcDir,
      statusPath,
      running,
      pluginVersion: ipcStatus && ipcStatus.version ? ipcStatus.version : null,
      mohoVersion: ipcStatus && ipcStatus.mohoVersion ? ipcStatus.mohoVersion : null,
      startedAt: ipcStatus && ipcStatus.startedAt ? ipcStatus.startedAt : null,
      versionMatch,
    },
    clients: detectedClients,
    nextSteps,
  };
}

export function runInstall(options = {}) {
  const apply = Boolean(options.apply);
  const scope = String(options.scope || "plugin").toLowerCase();
  if (!["plugin", "client", "all"].includes(scope)) {
    throw new Error(`Unsupported --scope '${scope}' (use plugin, client, or all)`);
  }
  const platform = options.platform || process.platform;
  const homeDir = options.homeDir || os.homedir();
  const pkgRoot = options.pkgRoot || PACKAGE_ROOT;
  const ipcDir = options.ipcDir ? path.resolve(options.ipcDir) : getIpcDir();
  const toolProfile = options.tools ? resolveToolProfile(options.tools) : "full";
  const removeLegacy = Boolean(options.removeLegacy);
  const useNpx = options.useNpx !== null && options.useNpx !== undefined ? Boolean(options.useNpx) : isNpxCacheDir(pkgRoot);

  const runPlugin = scope === "plugin" || scope === "all";
  const runClient = scope === "client" || scope === "all";
  const stamp = makeTimestamp();

  const report = {
    mode: apply ? "apply" : "dry_run",
    version: SERVER_INFO.version,
    scope,
    ipcDir,
    backups: [],
    removedLegacy: [],
  };

  let pluginPlan = null;
  if (runPlugin) {
    const scriptsInfo = resolveMohoScriptsDir({ cliDir: options.mohoScriptsDir, platform, homeDir });
    const pairs = buildPluginFilePairs(scriptsInfo.path, pkgRoot);
    const toolListPath = path.join(scriptsInfo.path, "Tool", "_tool_list.txt");
    const toolListExists = fs.existsSync(toolListPath);
    const legacyMenu = path.join(scriptsInfo.path, "Menu", "MohoMCP");
    const legacyTool = path.join(scriptsInfo.path, "Tool", "MohoMCP_Poller.lua");

    pluginPlan = {
      scriptsDir: scriptsInfo.path,
      scriptsDirExists: scriptsInfo.exists,
      menuDest: path.join(scriptsInfo.path, "Menu", "MohoStudioMCP"),
      toolDir: path.join(scriptsInfo.path, "Tool"),
      pairs,
      toolListPath,
      toolListExists,
      legacyMenu,
      legacyTool,
    };

    report.plugin = {
      scriptsDir: scriptsInfo.path,
      scriptsDirExists: scriptsInfo.exists,
      fileCount: pairs.length,
      menuDest: pluginPlan.menuDest,
      toolDest: path.join(pluginPlan.toolDir, "MohoStudioMCP_Poller.lua"),
      toolList: toolListExists ? toolListPath : null,
      legacyDetected: fs.existsSync(legacyMenu) || fs.existsSync(legacyTool),
    };
  }

  let clientPlans = [];
  if (runClient) {
    const allClients = getClientConfigPaths(platform, homeDir);
    let chosenNames = [];
    if (!options.clients || String(options.clients).trim().toLowerCase() === "auto") {
      chosenNames = Object.entries(allClients)
        .filter(([, cfg]) => fs.existsSync(cfg.path))
        .map(([name]) => name);
    } else {
      for (const raw of String(options.clients).split(",")) {
        const key = raw.trim().toLowerCase();
        if (!key) continue;
        if (!allClients[key]) {
          throw new Error(`Unknown client '${key}' (supported: auto, claude, cursor, antigravity, codex)`);
        }
        if (!chosenNames.includes(key)) chosenNames.push(key);
      }
    }
    if (chosenNames.length === 0) {
      throw new Error("No MCP client config detected. Pass --clients claude|cursor|antigravity|codex or configure your client manually.");
    }
    const spec = buildClientServerSpec({ useNpx, ipcDir, toolProfile, pkgRoot });
    for (const name of chosenNames) {
      clientPlans.push({ name, ...allClients[name], spec });
    }
    report.clients = clientPlans.map((c) => ({
      name: c.name,
      path: c.path,
      command: c.spec.command,
      args: c.spec.args,
      toolProfile,
    }));
  }

  if (!apply) {
    return report;
  }

  if (pluginPlan) {
    try {
      if (pluginPlan.toolListExists) {
        const bak = `${pluginPlan.toolListPath}.moho_studio_backup_${stamp}`;
        fs.copyFileSync(pluginPlan.toolListPath, bak);
        report.backups.push(bak);
      }

      if (removeLegacy) {
        if (fs.existsSync(pluginPlan.legacyMenu)) {
          fs.rmSync(pluginPlan.legacyMenu, { recursive: true, force: true });
          report.removedLegacy.push(pluginPlan.legacyMenu);
        }
        if (fs.existsSync(pluginPlan.legacyTool)) {
          fs.unlinkSync(pluginPlan.legacyTool);
          report.removedLegacy.push(pluginPlan.legacyTool);
        }
      }

      if (fs.existsSync(pluginPlan.menuDest)) {
        fs.rmSync(pluginPlan.menuDest, { recursive: true, force: true });
      }
      fs.mkdirSync(pluginPlan.menuDest, { recursive: true });
      fs.mkdirSync(pluginPlan.toolDir, { recursive: true });

      for (const p of pluginPlan.pairs) {
        fs.mkdirSync(path.dirname(p.dst), { recursive: true });
        fs.copyFileSync(p.src, p.dst);
      }

      if (pluginPlan.toolListExists) {
        const origRaw = fs.readFileSync(pluginPlan.toolListPath, "utf8");
        const newline = origRaw.includes("\r\n") ? "\r\n" : "\n";
        const updated = cleanToolListText(origRaw, removeLegacy).replace(/\n/g, newline);
        fs.writeFileSync(pluginPlan.toolListPath, updated, "utf8");
      }

      // Byte-for-byte SHA-256 readback verification
      for (const p of pluginPlan.pairs) {
        if (sha256File(p.src) !== sha256File(p.dst)) {
          throw new Error(`Verification failed after copy: ${p.label}`);
        }
      }
      report.plugin.verifiedFiles = pluginPlan.pairs.length;
    } catch (err) {
      if (err && (err.code === "EACCES" || err.code === "EPERM")) {
        throw new Error(
          `Permission denied writing to '${pluginPlan.scriptsDir}'. ` +
            "Run this command from an Administrator terminal (Windows) / sudo (macOS), " +
            "or pass --moho-scripts-dir \"<Your Moho Custom Content Folder>/Scripts\"."
        );
      }
      throw err;
    }
  }

  for (const cp of clientPlans) {
    fs.mkdirSync(path.dirname(cp.path), { recursive: true });
    if (fs.existsSync(cp.path)) {
      const bak = `${cp.path}.moho_studio_backup_${stamp}`;
      fs.copyFileSync(cp.path, bak);
      report.backups.push(bak);
    }
    if (cp.kind === "json") {
      let data = {};
      if (fs.existsSync(cp.path)) {
        const raw = fs.readFileSync(cp.path, "utf8").replace(/^\uFEFF/, "");
        data = raw.trim() ? JSON.parse(raw) : {};
      }
      if (!data.mcpServers || typeof data.mcpServers !== "object") {
        data.mcpServers = {};
      }
      data.mcpServers.moho = {
        command: cp.spec.command,
        args: cp.spec.args,
        env: cp.spec.env,
      };
      const outJson = JSON.stringify(data, null, 2) + "\n";
      fs.writeFileSync(cp.path, outJson, "utf8");
      const verify = JSON.parse(fs.readFileSync(cp.path, "utf8"));
      if (!verify.mcpServers || !verify.mcpServers.moho || verify.mcpServers.moho.command !== cp.spec.command) {
        throw new Error(`Readback verification failed for ${cp.path}`);
      }
    } else if (cp.kind === "toml") {
      const orig = fs.existsSync(cp.path) ? fs.readFileSync(cp.path, "utf8") : "";
      const stripped = stripTomlMohoSections(orig);
      const envLines = Object.entries(cp.spec.env)
        .map(([k, v]) => `${k} = ${JSON.stringify(v)}`)
        .join("\n");
      const block = [
        "",
        "[mcp_servers.moho]",
        `command = ${JSON.stringify(cp.spec.command)}`,
        `args = ${JSON.stringify(cp.spec.args)}`,
        "startup_timeout_sec = 30",
        "tool_timeout_sec = 60",
        "",
        "[mcp_servers.moho.env]",
        envLines,
        "",
      ].join("\n");
      const nextText = (stripped ? `${stripped}\n` : "") + block;
      fs.writeFileSync(cp.path, nextText, "utf8");
      const readback = fs.readFileSync(cp.path, "utf8");
      if (!readback.includes("[mcp_servers.moho]")) {
        throw new Error(`Readback verification failed for ${cp.path}`);
      }
    }
  }

  report.status = "installed_and_verified";
  return report;
}

function formatHelp() {
  return [
    `moho-studio-mcp v${SERVER_INFO.version} - Moho Pro 14.4 MCP server and setup CLI`,
    "",
    "Usage:",
    "  moho-studio-mcp [--tools full|core|rigging|animation|vector]",
    "      Start the stdio MCP server (default when no subcommand is given).",
    "",
    "  moho-studio-mcp install [--apply] [options]",
    "      Install the Moho Pro 14.4 Lua 5.4 plugin (dry-run by default).",
    "      --apply                     Execute copy/config writes with timestamped backups",
    "      --scope plugin|client|all   Target Moho plugin (default), MCP clients, or both",
    "      --moho-scripts-dir <dir>    Custom Moho Scripts folder (e.g. Custom Content Folder)",
    "      --clients <list>            auto (default), claude, cursor, antigravity, codex",
    "      --tools <profile>           Write MOHO_STUDIO_TOOLS profile into client config",
    "      --ipc-dir <dir>             Override shared IPC directory",
    "      --npx | --local-node        Force npx or local node path in client config",
    "      --remove-legacy             Remove old third-party MohoMCP plugin files",
    "      --json                      Output machine-readable JSON",
    "",
    "  moho-studio-mcp doctor [--json] [--moho-scripts-dir <dir>] [--ipc-dir <dir>]",
    "      Check Node version, Moho binary, installed Lua plugin parity, and live IPC status.",
    "",
    `Tool profiles: ${TOOL_PROFILES.join(", ")}`,
  ].join("\n");
}

function formatDoctorText(res) {
  const lines = [
    `Moho Studio MCP Doctor (v${res.server.version})`,
    `  Node.js:          ${res.node.version} (${res.node.supported ? "OK" : "UNSUPPORTED, requires >=20"})`,
    `  OS / Host Tier:   ${res.platform.os} (${res.platform.supportTier})`,
    `  Moho Executable:  ${res.mohoExecutable.exists ? "FOUND" : "NOT FOUND"} (${res.mohoExecutable.path})`,
    `  Scripts Folder:   ${res.plugin.scriptsDirExists ? "FOUND" : "NOT FOUND"} (${res.plugin.scriptsDir})`,
    `  Lua Plugin State: ${res.plugin.state} (${res.plugin.matchedFiles}/${res.plugin.totalBundledFiles} files match)`,
    `  _tool_list.txt:   ${res.plugin.toolListRegistered === null ? "not present (Custom Content Folder?)" : res.plugin.toolListRegistered ? "registered" : "missing MohoStudioMCP_Poller"}`,
    `  IPC Status:       ${res.ipc.running ? `RUNNING (plugin v${res.ipc.pluginVersion}, Moho ${res.ipc.mohoVersion})` : "NOT RUNNING"} (${res.ipc.dir})`,
  ];
  if (res.plugin.outdatedFiles.length > 0) {
    lines.push(`  Outdated Files:   ${res.plugin.outdatedFiles.join(", ")}`);
  }
  if (res.plugin.missingFiles.length > 0) {
    lines.push(`  Missing Files:    ${res.plugin.missingFiles.slice(0, 5).join(", ")}${res.plugin.missingFiles.length > 5 ? ` (+${res.plugin.missingFiles.length - 5} more)` : ""}`);
  }
  if (res.nextSteps.length > 0) {
    lines.push("", "Next steps:");
    for (const step of res.nextSteps) {
      lines.push(`  - ${step}`);
    }
  }
  return lines.join("\n");
}

export async function runCli(argv) {
  const cmd = argv[0];
  const flags = parseCliFlags(argv.slice(1));

  try {
    if (cmd === "--version" || cmd === "-v") {
      process.stdout.write(`moho-studio-mcp ${SERVER_INFO.version}\n`);
      return 0;
    }
    if (cmd === "--help" || cmd === "-h" || cmd === "help") {
      process.stdout.write(formatHelp() + "\n");
      return 0;
    }
    if (cmd === "doctor") {
      const res = runDoctor({
        mohoScriptsDir: flags.mohoScriptsDir,
        ipcDir: flags.ipcDir,
      });
      if (flags.json) {
        process.stdout.write(JSON.stringify(res, null, 2) + "\n");
      } else {
        process.stdout.write(formatDoctorText(res) + "\n");
      }
      return 0;
    }
    if (cmd === "install") {
      const res = runInstall(flags);
      process.stdout.write(JSON.stringify(res, null, 2) + "\n");
      return 0;
    }
    process.stderr.write(`Unknown command: ${cmd}\n\n${formatHelp()}\n`);
    return 1;
  } catch (err) {
    process.stderr.write(`Error: ${err.message || String(err)}\n`);
    return 1;
  }
}
