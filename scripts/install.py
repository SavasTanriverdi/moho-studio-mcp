"""Safe portable installer for Moho Studio MCP with dry-run, backups, verification, and legacy cleanup."""

import argparse
from datetime import datetime
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile
import tomllib


REPO = pathlib.Path(__file__).resolve().parents[1]
PROFILE = pathlib.Path.home()
CODEX_CFG = PROFILE / ".codex/config.toml"
AGY_CFG = PROFILE / ".gemini/config/mcp_config.json"
DEFAULT_MOHO_SCRIPTS = pathlib.Path(r"C:\Program Files\Moho 14\Resources\Support\Scripts")
DEFAULT_IPC_DIR = pathlib.Path(os.environ.get("MOHO_STUDIO_IPC_DIR") or (pathlib.Path(tempfile.gettempdir()) / "moho-studio-mcp"))
LEGACY_RUNTIME_DIR = PROFILE / ".local/share/agent-tools/moho-mcp"


def resolve_node_path(cli_node=None):
    candidate = cli_node or os.environ.get("NODE_EXE") or shutil.which("node")
    if not candidate:
        raise RuntimeError("Node.js executable not found on PATH; install Node.js 20+ or pass --node <path>")
    node_path = pathlib.Path(candidate).resolve()
    if not node_path.is_file():
        raise RuntimeError(f"Node executable not found: {node_path}")
    return node_path


def parse_clients(clients_arg):
    if not clients_arg or clients_arg.strip().lower() == "auto":
        detected = []
        if CODEX_CFG.is_file():
            detected.append("codex")
        if AGY_CFG.is_file():
            detected.append("antigravity")
        return detected
    valid = {"codex", "antigravity"}
    chosen = []
    for item in clients_arg.split(","):
        k = item.strip().lower()
        if not k:
            continue
        if k not in valid:
            raise RuntimeError(f"Unknown client '{k}' (supported: auto, codex, antigravity)")
        if k not in chosen:
            chosen.append(k)
    return chosen


def strip_toml_moho_sections(text):
    """Remove any existing [mcp_servers.moho] and [mcp_servers.moho.*] sections cleanly."""
    lines = text.splitlines(keepends=True)
    out = []
    skipping = False
    header_re = re.compile(r"^\s*\[([^\]]+)\]\s*$")
    for line in lines:
        m = header_re.match(line)
        if m:
            sec = m.group(1).strip()
            if sec == "mcp_servers.moho" or sec.startswith("mcp_servers.moho."):
                skipping = True
                continue
            skipping = False
        if not skipping:
            out.append(line)
    return "".join(out)


def prepare_user_plan(node_path, ipc_dir, clients):
    entry_script = REPO / "src/server.mjs"
    if not entry_script.is_file():
        raise RuntimeError(f"MCP server entry script missing: {entry_script}")
    if not clients:
        raise RuntimeError(
            "No supported MCP client config found (~/.codex/config.toml or ~/.gemini/config/mcp_config.json). "
            "See README.md for manual Claude Desktop / Cursor / generic MCP client configuration."
        )

    plan = {
        "node_path": str(node_path),
        "entry_script": str(entry_script),
        "ipc_dir": str(ipc_dir),
        "clients": list(clients),
        "client_configs": [],
        "codex": None,
        "antigravity": None,
        "legacy_runtime_exists": LEGACY_RUNTIME_DIR.exists(),
    }

    if "codex" in clients:
        if not CODEX_CFG.is_file():
            raise RuntimeError(f"Codex config not found: {CODEX_CFG}")
        codex_orig = CODEX_CFG.read_bytes()
        codex_before = tomllib.loads(codex_orig.decode("utf-8-sig"))
        codex_stripped = strip_toml_moho_sections(codex_orig.decode("utf-8-sig")).rstrip()
        addition = (
            "\n\n[mcp_servers.moho]\n"
            f"command = {json.dumps(str(node_path))}\n"
            f"args = {json.dumps([str(entry_script)])}\n"
            "startup_timeout_sec = 30\n"
            "tool_timeout_sec = 60\n\n"
            "[mcp_servers.moho.env]\n"
            f"MOHO_STUDIO_IPC_DIR = {json.dumps(str(ipc_dir))}\n"
        )
        codex_new = codex_stripped + addition
        codex_after = tomllib.loads(codex_new)

        before_root = dict(codex_before)
        after_root = dict(codex_after)
        before_srv = dict(before_root.get("mcp_servers", {}))
        after_srv = dict(after_root.get("mcp_servers", {}))
        before_srv.pop("moho", None)
        after_srv.pop("moho", None)
        before_root["mcp_servers"] = before_srv
        after_root["mcp_servers"] = after_srv
        if before_root != after_root:
            raise RuntimeError("Codex config diff check failed: unrelated settings changed")

        plan["codex"] = {"path": CODEX_CFG, "orig": codex_orig, "new": codex_new}
        plan["client_configs"].append(str(CODEX_CFG))

    if "antigravity" in clients:
        if not AGY_CFG.is_file():
            raise RuntimeError(f"Antigravity config not found: {AGY_CFG}")
        agy_orig = AGY_CFG.read_bytes()
        agy_before = json.loads(agy_orig.decode("utf-8-sig"))
        agy_after = json.loads(json.dumps(agy_before))
        agy_after.setdefault("mcpServers", {})["moho"] = {
            "command": str(node_path),
            "args": [str(entry_script)],
            "env": {"MOHO_STUDIO_IPC_DIR": str(ipc_dir)},
        }
        agy_new = json.dumps(agy_after, indent=2, ensure_ascii=True) + "\n"
        plan["antigravity"] = {"path": AGY_CFG, "orig": agy_orig, "after": agy_after, "new": agy_new}
        plan["client_configs"].append(str(AGY_CFG))

    return plan


def apply_user_plan(plan, stamp, remove_legacy):
    backups = []
    if plan["codex"]:
        target = plan["codex"]["path"]
        bak = target.with_name(f"{target.name}.moho_studio_backup_{stamp}")
        shutil.copy2(target, bak)
        backups.append(str(bak))
        if target.read_bytes() != plan["codex"]["orig"]:
            raise RuntimeError("Codex config changed mid-install; inspect backup")
        target.write_text(plan["codex"]["new"], encoding="utf-8", newline="\n")
        check_codex = tomllib.loads(target.read_text("utf-8"))
        if check_codex["mcp_servers"]["moho"]["args"] != [plan["entry_script"]]:
            raise RuntimeError("Codex readback verification failed")

    if plan["antigravity"]:
        target = plan["antigravity"]["path"]
        bak = target.with_name(f"{target.name}.moho_studio_backup_{stamp}")
        shutil.copy2(target, bak)
        backups.append(str(bak))
        if target.read_bytes() != plan["antigravity"]["orig"]:
            raise RuntimeError("Antigravity config changed mid-install; inspect backup")
        target.write_text(plan["antigravity"]["new"], encoding="utf-8", newline="\n")
        check_agy = json.loads(target.read_text("utf-8"))
        if check_agy != plan["antigravity"]["after"]:
            raise RuntimeError("Antigravity readback verification failed")

    removed_legacy = []
    if remove_legacy and LEGACY_RUNTIME_DIR.exists():
        shutil.rmtree(LEGACY_RUNTIME_DIR)
        removed_legacy.append(str(LEGACY_RUNTIME_DIR))

    return backups, removed_legacy


def clean_tool_list_text(text, remove_legacy):
    lines = text.replace("\r\n", "\n").splitlines()
    out = []
    for line in lines:
        if remove_legacy and ("/Tools/Group/MohoMCP=" in line or "MohoMCP_Poller" in line):
            continue
        if "/Tools/Group/MohoStudioMCP=" in line or "MohoStudioMCP_Poller" in line:
            continue
        out.append(line)
    while out and out[-1].strip() == "":
        out.pop()
    out.append("")
    out.append('group MOHO.Localize("/Tools/Group/MohoStudioMCP=MohoStudioMCP")')
    out.append("tool\tMohoStudioMCP_Poller\t...")
    return "\n".join(out) + "\n"


def prepare_plugin_plan(moho_scripts_dir, remove_legacy):
    plugin_src = REPO / "moho-plugin"
    if not (plugin_src / "MohoStudioMCP_Server.lua").is_file():
        raise RuntimeError("Plugin source missing")
    menu_dest = moho_scripts_dir / "Menu/MohoStudioMCP"
    tool_dest = moho_scripts_dir / "Tool/MohoStudioMCP_Poller.lua"
    tool_list = moho_scripts_dir / "Tool/_tool_list.txt"
    legacy_menu = moho_scripts_dir / "Menu/MohoMCP"
    legacy_tool = moho_scripts_dir / "Tool/MohoMCP_Poller.lua"

    tool_list_exists = tool_list.is_file()
    tool_orig = tool_list.read_bytes() if tool_list_exists else b""
    newline = "\r\n" if b"\r\n" in tool_orig else "\n"
    tool_new = clean_tool_list_text(tool_orig.decode("utf-8-sig"), remove_legacy) if tool_list_exists else None

    return {
        "plugin_src": plugin_src,
        "menu_dest": menu_dest,
        "tool_dest": tool_dest,
        "tool_list": tool_list,
        "tool_list_exists": tool_list_exists,
        "tool_orig": tool_orig,
        "tool_new": tool_new,
        "newline": newline,
        "legacy_menu": legacy_menu,
        "legacy_tool": legacy_tool,
        "legacy_menu_exists": legacy_menu.exists(),
        "legacy_tool_exists": legacy_tool.exists(),
    }


def apply_plugin_plan(plan, stamp, remove_legacy):
    backups = []
    removed = []

    if plan["tool_list_exists"]:
        bak = plan["tool_list"].with_name(f"{plan['tool_list'].name}.moho_studio_backup_{stamp}")
        shutil.copy2(plan["tool_list"], bak)
        backups.append(str(bak))

    if remove_legacy:
        if plan["legacy_menu"].exists():
            shutil.rmtree(plan["legacy_menu"])
            removed.append(str(plan["legacy_menu"]))
        if plan["legacy_tool"].exists():
            plan["legacy_tool"].unlink()
            removed.append(str(plan["legacy_tool"]))

    if plan["menu_dest"].exists():
        shutil.rmtree(plan["menu_dest"])
    plan["menu_dest"].mkdir(parents=True, exist_ok=True)
    plan["tool_dest"].parent.mkdir(parents=True, exist_ok=True)

    src = plan["plugin_src"]
    shutil.copy2(src / "MohoStudioMCP_Server.lua", plan["menu_dest"] / "MohoStudioMCP_Server.lua")
    shutil.copytree(src / "moho_studio", plan["menu_dest"] / "moho_studio")
    shutil.copy2(src / "MohoStudioMCP_Poller.lua", plan["tool_dest"])

    icon_files = [
        "MohoStudioMCP_Poller.png",
        "MohoStudioMCP_Poller@2x.png",
        "MohoStudioMCP_Poller_large.png",
    ]
    for icon_name in icon_files:
        icon_src = src / icon_name
        if icon_src.is_file():
            shutil.copy2(icon_src, plan["tool_dest"].parent / icon_name)

    if plan["tool_list_exists"]:
        if plan["tool_list"].read_bytes() != plan["tool_orig"]:
            raise RuntimeError("_tool_list.txt changed mid-install; inspect backup")
        plan["tool_list"].write_text(plan["tool_new"], encoding="utf-8", newline=plan["newline"])

    # Byte-for-byte verification of every installed Lua and icon file
    if (plan["menu_dest"] / "MohoStudioMCP_Server.lua").read_bytes() != (src / "MohoStudioMCP_Server.lua").read_bytes():
        raise RuntimeError("Verification failed: MohoStudioMCP_Server.lua")
    if plan["tool_dest"].read_bytes() != (src / "MohoStudioMCP_Poller.lua").read_bytes():
        raise RuntimeError("Verification failed: MohoStudioMCP_Poller.lua")
    for icon_name in icon_files:
        icon_src = src / icon_name
        if icon_src.is_file():
            icon_dst = plan["tool_dest"].parent / icon_name
            if icon_dst.read_bytes() != icon_src.read_bytes():
                raise RuntimeError(f"Verification failed: {icon_name}")
    for lua_src in (src / "moho_studio").rglob("*.lua"):
        rel = lua_src.relative_to(src / "moho_studio")
        dst = plan["menu_dest"] / "moho_studio" / rel
        if dst.read_bytes() != lua_src.read_bytes():
            raise RuntimeError(f"Verification failed: {dst}")

    return backups, removed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--scope", choices=("all", "user", "moho-plugin"), default="all")
    parser.add_argument("--clients", default="auto", help="Clients to configure: auto, codex, antigravity, or comma-separated")
    parser.add_argument("--node", default=None, help="Path to Node.js 20+ executable (defaults to NODE_EXE or PATH)")
    parser.add_argument("--ipc-dir", default=str(DEFAULT_IPC_DIR), help="IPC directory shared between Node server and Moho Lua plugin")
    parser.add_argument("--remove-legacy", action="store_true", help="Remove old third-party MohoMCP files")
    parser.add_argument("--moho-scripts-dir", default=str(DEFAULT_MOHO_SCRIPTS))
    args = parser.parse_args()

    moho_scripts_dir = pathlib.Path(args.moho_scripts_dir)
    ipc_dir = pathlib.Path(args.ipc_dir)
    run_user = args.scope in ("all", "user")
    run_plugin = args.scope in ("all", "moho-plugin")

    user_plan = None
    if run_user:
        node_path = resolve_node_path(args.node)
        clients = parse_clients(args.clients)
        user_plan = prepare_user_plan(node_path, ipc_dir, clients)

    plugin_plan = prepare_plugin_plan(moho_scripts_dir, args.remove_legacy) if run_plugin else None

    report = {
        "mode": "apply" if args.apply else "dry_run",
        "scope": args.scope,
        "remove_legacy": args.remove_legacy,
        "repo": str(REPO),
        "ipc_dir": str(ipc_dir),
    }
    if run_user:
        report["node"] = user_plan["node_path"]
        report["server_entry"] = user_plan["entry_script"]
        report["clients"] = user_plan["clients"]
        report["client_configs"] = user_plan["client_configs"]
        report["legacy_runtime_detected"] = user_plan["legacy_runtime_exists"]
    if run_plugin:
        report["moho_menu_dest"] = str(plugin_plan["menu_dest"])
        report["moho_tool_dest"] = str(plugin_plan["tool_dest"])
        report["moho_tool_list"] = str(plugin_plan["tool_list"]) if plugin_plan["tool_list_exists"] else None
        report["legacy_plugin_detected"] = plugin_plan["legacy_menu_exists"] or plugin_plan["legacy_tool_exists"]

    if not args.apply:
        print(json.dumps(report, indent=2))
        return

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backups = []
    removed = []
    if run_user:
        b, r = apply_user_plan(user_plan, stamp, args.remove_legacy)
        backups.extend(b)
        removed.extend(r)
    if run_plugin:
        b, r = apply_plugin_plan(plugin_plan, stamp, args.remove_legacy)
        backups.extend(b)
        removed.extend(r)

    report["status"] = "installed_and_verified"
    report["backups"] = backups
    report["removed_legacy"] = removed
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("Install error: " + str(exc), file=sys.stderr)
        sys.exit(1)
