#!/usr/bin/env bash
# setup-opensearch-mcp.sh
# Sets up OpenSearch MCP stdio proxy + Cursor mcp.json entries (WSL / Linux)
set -euo pipefail

HOME_DIR="${HOME}"
VENV_DIR="${HOME_DIR}/venv"
PROXY_PY="${HOME_DIR}/opensearch_mcp_proxy.py"
MCP_JSON="${HOME_DIR}/.cursor/mcp.json"

# Default auth / SSL for all OpenSearch MCP proxies (override via env if needed)
OPENSEARCH_MCP_AUTH_B64="${OPENSEARCH_MCP_AUTH_B64:-bWNwX2FnZW50OjBiUUFEdzNVVklZOCtEVzRGOU1Kd0RBRGIxamIySDVSb3NKYndSU3JJOEE9}"
OPENSEARCH_SSL_VERIFY="${OPENSEARCH_SSL_VERIFY:-false}"
MCP_PROXY_DEBUG="${MCP_PROXY_DEBUG:-0}"

echo "==> Home: ${HOME_DIR}"
echo "==> Venv: ${VENV_DIR}"
echo "==> Proxy: ${PROXY_PY}"
echo "==> mcp.json: ${MCP_JSON}"

# ---------------------------------------------------------------------------
# 1) Create venv + install deps
# ---------------------------------------------------------------------------
if [[ ! -d "${VENV_DIR}" ]]; then
  echo "==> Creating venv..."
  python3 -m venv "${VENV_DIR}"
else
  echo "==> Venv already exists, reusing."
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
pip install -U pip
pip install "mcp" "httpx" "httpx-sse"

PYTHON_BIN="${VENV_DIR}/bin/python3"

# ---------------------------------------------------------------------------
# 2) Write proxy script
# ---------------------------------------------------------------------------
echo "==> Writing ${PROXY_PY}..."
cat > "${PROXY_PY}" << 'PROXY_EOF'
#!/usr/bin/env python3
"""MCP stdio bridge to OpenSearch native MCP HTTP endpoint.

Cursor speaks MCP over stdio to this process. Initialize and lifecycle
notifications are handled locally by the MCP SDK. Tool listing and execution
are forwarded to OpenSearch POST /_plugins/_ml/mcp.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from typing import Any

import httpx
from httpx_sse import EventSource
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import CallToolResult, TextContent, Tool

JSON = "application/json"
SSE = "text/event-stream"

DEFAULT_INSTRUCTIONS = (
    "OpenSearch MCP bridge - exposes cluster-registered ML tools "
    "(ListIndexTool, SearchIndexTool, SearchAlertsTool, LogPatternTool, etc.)"
)


def _log(msg: str) -> None:
    if os.environ.get("MCP_PROXY_DEBUG") == "1":
        print(f"[opensearch-mcp-bridge] {msg}", file=sys.stderr, flush=True)


def _env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def _normalize_input_schema(schema: dict[str, Any] | None) -> dict[str, Any]:
    if not schema:
        return {"type": "object", "properties": {}}
    if schema.get("type") is None and "properties" not in schema:
        return {"type": "object", "properties": {}}
    return schema


@dataclass
class OpenSearchMcpBackend:
    client: httpx.AsyncClient
    url: str
    _request_id: int = 0

    def _next_id(self) -> int:
        self._request_id += 1
        return self._request_id

    async def _read_response(self, response: httpx.Response) -> dict[str, Any]:
        content_type = response.headers.get("content-type", "").lower()
        if content_type.startswith(JSON):
            return json.loads((await response.aread()).decode("utf-8"))
        if SSE in content_type:
            event_source = EventSource(response)
            async for event in event_source.aiter_sse():
                if event.event == "message" and event.data:
                    return json.loads(event.data)
            raise RuntimeError("OpenSearch MCP returned empty SSE stream")
        body = await response.aread()
        raise RuntimeError(f"Unexpected content-type: {content_type!r} body={body[:200]!r}")

    async def rpc(self, method: str, params: dict[str, Any] | None = None) -> Any:
        payload = {
            "jsonrpc": "2.0",
            "id": self._next_id(),
            "method": method,
            "params": params or {},
        }
        headers = {
            "Authorization": f"Basic {_env('OPENSEARCH_MCP_AUTH_B64')}",
            "Content-Type": JSON,
            "Accept": f"{JSON}, {SSE}",
        }
        _log(f"→ {method}")
        async with self.client.stream("POST", self.url, json=payload, headers=headers) as response:
            if response.status_code == 202:
                return None
            response.raise_for_status()
            data = await self._read_response(response)

        if "error" in data:
            error = data["error"]
            message = error.get("message", "unknown OpenSearch MCP error")
            code = error.get("code", -32603)
            raise RuntimeError(f"OpenSearch MCP error {code}: {message}")
        return data.get("result")

    async def fetch_instructions(self) -> str:
        try:
            result = await self.rpc(
                "initialize",
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "opensearch-mcp-bridge", "version": "1.0.0"},
                },
            )
            if isinstance(result, dict):
                instructions = result.get("instructions")
                if instructions:
                    return instructions
        except Exception as exc:
            _log(f"Could not fetch instructions from OpenSearch: {exc}")
        return DEFAULT_INSTRUCTIONS

    async def list_tools(self) -> list[Tool]:
        result = await self.rpc("tools/list")
        tools: list[Tool] = []
        for item in (result or {}).get("tools", []):
            tools.append(
                Tool(
                    name=item["name"],
                    description=item.get("description"),
                    inputSchema=_normalize_input_schema(item.get("inputSchema")),
                )
            )
        _log(f"← tools/list returned {len(tools)} tools")
        return tools

    async def call_tool(self, name: str, arguments: dict[str, Any] | None) -> list[TextContent] | CallToolResult:
        result = await self.rpc("tools/call", {"name": name, "arguments": arguments or {}})
        if not isinstance(result, dict):
            return [TextContent(type="text", text=json.dumps(result, indent=2))]

        content_blocks = result.get("content") or []
        text_blocks: list[TextContent] = []
        for block in content_blocks:
            if isinstance(block, dict) and block.get("type") == "text":
                text_blocks.append(TextContent(type="text", text=block.get("text", "")))
            else:
                text_blocks.append(TextContent(type="text", text=json.dumps(block, indent=2)))

        if not text_blocks:
            text_blocks = [TextContent(type="text", text=json.dumps(result, indent=2))]

        if result.get("isError"):
            return CallToolResult(content=text_blocks, isError=True)
        return text_blocks


async def run_bridge() -> None:
    url = _env("OPENSEARCH_MCP_URL")
    verify = os.environ.get("OPENSEARCH_SSL_VERIFY", "true").lower() not in ("0", "false", "no")
    timeout = float(os.environ.get("OPENSEARCH_MCP_TIMEOUT", "120"))

    _log(f"Bridge starting → {url} (ssl_verify={verify})")

    async with httpx.AsyncClient(verify=verify, timeout=timeout) as client:
        backend = OpenSearchMcpBackend(client=client, url=url)
        server = Server("opensearch-mcp-bridge", instructions=DEFAULT_INSTRUCTIONS)

        @server.list_tools()
        async def handle_list_tools() -> list[Tool]:
            return await backend.list_tools()

        @server.call_tool(validate_input=False)
        async def handle_call_tool(name: str, arguments: dict[str, Any] | None) -> list[TextContent] | CallToolResult:
            return await backend.call_tool(name, arguments)

        options = server.create_initialization_options()
        async with stdio_server() as (read_stream, write_stream):
            await server.run(read_stream, write_stream, options, raise_exceptions=True)


def main() -> None:
    import asyncio

    asyncio.run(run_bridge())


if __name__ == "__main__":
    main()
PROXY_EOF

chmod +x "${PROXY_PY}"

# ---------------------------------------------------------------------------
# 3) Merge MCP servers into WSL + Windows Cursor mcp.json (append, never wipe)
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/.cursor"

# Windows Cursor config path (override with WIN_MCP_JSON env if needed)
if [[ -z "${WIN_MCP_JSON:-}" ]]; then
  if [[ -d "/mnt/c/Users/Soham.Mahadik/.cursor" ]]; then
    WIN_MCP_JSON="/mnt/c/Users/Soham.Mahadik/.cursor/mcp.json"
  elif compgen -G "/mnt/c/Users/*/.cursor" > /dev/null 2>&1; then
    WIN_MCP_JSON="$(ls -d /mnt/c/Users/*/.cursor 2>/dev/null | head -1)/mcp.json"
  else
    WIN_MCP_JSON=""
  fi
fi

if [[ -f "${MCP_JSON}" ]]; then
  cp -a "${MCP_JSON}" "${MCP_JSON}.bak.$(date +%Y%m%d%H%M%S)"
  echo "==> Backed up existing WSL mcp.json"
fi

if [[ -n "${WIN_MCP_JSON}" && -f "${WIN_MCP_JSON}" ]]; then
  cp -a "${WIN_MCP_JSON}" "${WIN_MCP_JSON}.bak.$(date +%Y%m%d%H%M%S)"
  echo "==> Backed up existing Windows mcp.json"
fi

"${PYTHON_BIN}" - << PY
import json
import glob
from pathlib import Path

mcp_path = Path(${MCP_JSON@Q})
win_mcp_path = Path(${WIN_MCP_JSON@Q}) if ${WIN_MCP_JSON@Q} else None
python_bin = ${PYTHON_BIN@Q}
proxy_py = ${PROXY_PY@Q}
auth_b64 = ${OPENSEARCH_MCP_AUTH_B64@Q}
ssl_verify = ${OPENSEARCH_SSL_VERIFY@Q}
proxy_debug = ${MCP_PROXY_DEBUG@Q}

def opensearch_server(url: str) -> dict:
    return {
        "command": python_bin,
        "args": [proxy_py],
        "env": {
            "OPENSEARCH_MCP_URL": url,
            "OPENSEARCH_MCP_AUTH_B64": auth_b64,
            "OPENSEARCH_SSL_VERIFY": ssl_verify,
            "MCP_PROXY_DEBUG": proxy_debug,
        },
    }

new_servers = {
    "enola": {
        "command": "enola",
    },
    "opensearch-infra": opensearch_server(
        "https://infralogs.elk.inf.use1.cwcoreentityprod.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-itboost": opensearch_server(
        "https://logs.elk.inf.use1.cwitboostdev.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-datadev": opensearch_server(
        "https://logs.elk.inf.use1.cwdatadev.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-platform-au": opensearch_server(
        "https://logs.elk.inf.apse2.cwdataprod.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-psa-au": opensearch_server(
        "https://logs.elk.inf.apse2.cwprod.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-platform-eu": opensearch_server(
        "https://logs.elk.inf.euw1.cwdataprod.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-psa-eu": opensearch_server(
        "https://logs.elk.inf.euw1.cwprod.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-psa-na": opensearch_server(
        "https://logs.elk.inf.use1.cwprod.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "opensearch-platform-na": opensearch_server(
        "https://logs.elk.inf.use1.cwdataprod.cwnet.io:9200/_plugins/_ml/mcp"
    ),
    "jenkins": {
        "url": "https://prodansible.cwcloudplatform.cwnet.io/mcp-server/mcp",
        "headers": {
            "Authorization": "Basic c3ZjLWplbmtpbnMtbWNwOjExMjkzN2ZmY2M1MzJjM2UyNGY5NjgyOTYxMDFjMGZmMjg="
        },
    },
}

def load_mcp(path: Path) -> dict:
    if path.exists() and path.read_text().strip():
        data = json.loads(path.read_text())
        if not isinstance(data, dict):
            raise SystemExit(f"{path} root must be an object")
        return data
    return {}

def merge_servers(path: Path, servers_patch: dict) -> tuple[list[str], list[str]]:
    data = load_mcp(path)
    servers = data.setdefault("mcpServers", {})
    if not isinstance(servers, dict):
        raise SystemExit(f"{path}: mcpServers must be an object")
    added, updated = [], []
    for name, block in servers_patch.items():
        (updated if name in servers else added).append(name)
        servers[name] = block
    if "opensearch" in servers and "opensearch-infra" in servers:
        del servers["opensearch"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    return added, updated

def to_windows_server(block: dict) -> dict:
    if "url" in block:
        return block
    if block.get("command") == "enola":
        return {"command": "wsl.exe", "args": ["enola"]}
    return {
        "command": "wsl.exe",
        "args": [python_bin, proxy_py],
        "env": block.get("env", {}),
    }

# --- WSL Cursor config (native Linux paths) ---
wsl_added, wsl_updated = merge_servers(mcp_path, new_servers)
print(f"==> WSL config:  {mcp_path}")
print(f"==>   Added ({len(wsl_added)}): {', '.join(wsl_added) if wsl_added else 'none'}")
print(f"==>   Updated ({len(wsl_updated)}): {', '.join(wsl_updated) if wsl_updated else 'none'}")

# --- Windows Cursor config (via wsl.exe) ---
if win_mcp_path is None:
    candidates = [Path(p) / "mcp.json" for p in glob.glob("/mnt/c/Users/*/.cursor")]
    win_mcp_path = candidates[0] if candidates else None

if win_mcp_path is not None:
    win_servers = {name: to_windows_server(block) for name, block in new_servers.items()}
    win_added, win_updated = merge_servers(win_mcp_path, win_servers)
    print(f"==> Windows config: {win_mcp_path}")
    print(f"==>   Added ({len(win_added)}): {', '.join(win_added) if win_added else 'none'}")
    print(f"==>   Updated ({len(win_updated)}): {', '.join(win_updated) if win_updated else 'none'}")
else:
    print("==> Windows Cursor path not found under /mnt/c/Users/*/.cursor — skipped")

all_keys = sorted(load_mcp(mcp_path).get("mcpServers", {}).keys())
print("==> MCP server keys:", ", ".join(all_keys))
PY

echo
echo "Done."
echo "  Python:       ${PYTHON_BIN}"
echo "  Proxy:        ${PROXY_PY}"
echo "  WSL config:   ${MCP_JSON}"
if [[ -n "${WIN_MCP_JSON:-}" ]]; then
  echo "  Windows config: ${WIN_MCP_JSON}"
fi
echo
echo "MCP servers configured (WSL + Windows where available):"
echo "  - enola"
echo "  - opensearch-infra"
echo "  - opensearch-itboost"
echo "  - opensearch-datadev"
echo "  - opensearch-platform-au"
echo "  - opensearch-psa-au"
echo "  - opensearch-platform-eu"
echo "  - opensearch-psa-eu"
echo "  - opensearch-psa-na"
echo "  - opensearch-platform-na"
echo "  - jenkins"
echo
echo "Restart Cursor (or reload MCP servers) to pick up the changes."
