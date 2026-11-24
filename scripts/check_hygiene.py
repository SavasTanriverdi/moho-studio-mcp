"""Verify text hygiene (UTF-8/ASCII), JS syntax, and Node-to-Lua RPC contract alignment."""

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys


REPO = pathlib.Path(__file__).resolve().parents[1]
TEXT_EXTS = {".mjs", ".lua", ".py", ".json", ".md", ".yml", ".yaml", ".txt", ".gitignore", ".editorconfig"}
ASCII_STRICT_EXTS = {".mjs", ".lua", ".py", ".json", ".yml", ".yaml", ".txt"}


def resolve_node(cli_node=None):
    if cli_node:
        return cli_node
    env_node = os.environ.get("NODE_EXE")
    if env_node:
        return env_node
    return shutil.which("node") or "node"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default=None, help="Path to Node.js executable (defaults to NODE_EXE or PATH)")
    args = parser.parse_args()

    errors = []
    checked = 0
    for path in sorted(REPO.rglob("*")):
        if not path.is_file():
            continue
        if ".git" in path.parts or "__pycache__" in path.parts:
            continue
        if path.suffix.lower() not in TEXT_EXTS and path.name not in TEXT_EXTS:
            continue
        checked += 1
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            errors.append(f"{path.relative_to(REPO)}: invalid UTF-8 ({exc})")
            continue
        if "\ufffd" in text:
            errors.append(f"{path.relative_to(REPO)}: contains U+FFFD replacement character")
        if path.suffix.lower() in ASCII_STRICT_EXTS:
            for idx, line in enumerate(text.splitlines(), 1):
                for ch in line:
                    if ord(ch) > 127:
                        errors.append(f"{path.relative_to(REPO)}:{idx}: non-ASCII character U+{ord(ch):04X}")
                        break

    # Check Node syntax on all .mjs files
    node_exe = resolve_node(args.node)
    for mjs in sorted(REPO.rglob("*.mjs")):
        if ".git" in mjs.parts:
            continue
        proc = subprocess.run([node_exe, "--check", str(mjs)], capture_output=True, text=True)
        if proc.returncode != 0:
            errors.append(f"node --check failed for {mjs.relative_to(REPO)}: {proc.stderr.strip()}")

    # Static Lua syntax balance check (trailing commas before ')', parens/braces/brackets, block balance)
    lua_checked = 0
    for lua_path in sorted((REPO / "moho-plugin").rglob("*.lua")):
        lua_checked += 1
        txt = lua_path.read_text("utf-8")
        clean = re.sub(r"--\[\[.*?\]\]", "", txt, flags=re.S)
        clean = re.sub(r"--[^\n]*", "", clean)
        clean = re.sub(r'"(?:\\.|[^"\\])*"', '""', clean)
        clean = re.sub(r"'(?:\\.|[^'\\])*'", "''", clean)
        for m in re.finditer(r",\s*\)", clean):
            line_no = clean[: m.start()].count("\n") + 1
            errors.append(f"{lua_path.relative_to(REPO)}:{line_no}: trailing comma before ')'")
        for op, cl in (("(", ")"), ("{", "}"), ("[", "]")):
            if clean.count(op) != clean.count(cl):
                errors.append(
                    f"{lua_path.relative_to(REPO)}: unbalanced {op}{cl} ({clean.count(op)} vs {clean.count(cl)})"
                )
        tokens = re.findall(r"\b(?:function|then|do|repeat|until|end|elseif)\b", clean)
        depth = 0
        for tok in tokens:
            if tok in ("function", "then", "do", "repeat"):
                depth += 1
            elif tok == "elseif":
                depth -= 1
            elif tok in ("end", "until"):
                depth -= 1
        if depth != 0:
            errors.append(f"{lua_path.relative_to(REPO)}: unbalanced Lua block keywords (depth={depth})")

    # Verify every rpcMethod declared in src/tools.mjs is registered in MohoStudioMCP_Server.lua
    tools_src = (REPO / "src/tools.mjs").read_text("utf-8")
    lua_srv = (REPO / "moho-plugin/MohoStudioMCP_Server.lua").read_text("utf-8")
    node_methods = set(re.findall(r'rpcMethod:\s*"([^"]+)"', tools_src))
    lua_methods = set(re.findall(r'\{\s*"([a-z]+\.[a-zA-Z]+)"\s*,', lua_srv))
    missing_in_lua = sorted(node_methods - lua_methods)
    missing_in_node = sorted(lua_methods - node_methods)
    if missing_in_lua:
        errors.append(f"RPC methods declared in src/tools.mjs but missing in Lua server: {missing_in_lua}")
    if missing_in_node:
        errors.append(f"RPC methods registered in Lua server but missing in src/tools.mjs: {missing_in_node}")

    if errors:
        for e in errors:
            print("ERROR:", e, file=sys.stderr)
        sys.exit(1)

    print(
        f"HYGIENE OK: {checked} files checked, {lua_checked} Lua files balanced, {len(node_methods)} RPC methods matched 1:1, 0 errors"
    )


if __name__ == "__main__":
    main()
