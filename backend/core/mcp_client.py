"""
MCP-Client – kommuniziert mit MCP-Servern via Streamable HTTP.

MCP (Model Context Protocol) ist ein offenes Standard-Protokoll von Anthropic
für Tool-Calling. Jeder MCP-Server wird über HTTP angesprochen.

Protokoll:
- POST /mcp mit JSON-RPC 2.0 Nachrichten
- Methoden: initialize, tools/list, tools/call
- Server kann direkt JSON ODER SSE (text/event-stream) zurückgeben
"""

import json
import logging
from typing import Any, Dict, List, Optional

import httpx

from tools.base import BaseTool, ToolInfo, ToolParameter

logger = logging.getLogger(__name__)


def _parse_mcp_response(resp: httpx.Response) -> Dict[str, Any]:
    """
    Parst eine MCP-Server-Antwort – unterstützt JSON und SSE.

    MCP Streamable HTTP erlaubt dem Server, JSON-RPC-Antworten entweder als
    direktes JSON oder als SSE-Stream zu senden. SSE-Zeilen haben das Format:
        event: message
        data: {"jsonrpc":"2.0","id":1,"result":{...}}
    """
    content_type = resp.headers.get("content-type", "")
    if "text/event-stream" in content_type:
        for line in resp.text.splitlines():
            if line.startswith("data:"):
                payload = line[5:].strip()
                if payload:
                    return json.loads(payload)
        return {}
    return resp.json()


class MCPTool(BaseTool):
    """
    Repräsentiert ein einzelnes Tool von einem MCP-Server.
    Leitet Ausführung an den MCP-Server weiter.
    """

    def __init__(
        self,
        tool_def: Dict[str, Any],
        server_url: str,
        api_key: Optional[str] = None,
    ):
        self.name = tool_def["name"]
        self.description = tool_def.get("description", "")
        self.server_url = server_url.rstrip("/")
        self.api_key = api_key
        self._raw_schema = tool_def.get("inputSchema", {})

        # JSON-Schema in ToolParameter konvertieren
        props = self._raw_schema.get("properties", {})
        required_params = self._raw_schema.get("required", [])
        self.parameters = {
            pname: ToolParameter(
                type=prop.get("type", "string"),
                description=prop.get("description", pname),
                required=pname in required_params,
            )
            for pname, prop in props.items()
        }

    def _headers(self) -> Dict[str, str]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return headers

    async def execute(self, arguments: Dict[str, Any]) -> str:
        """Sendet tools/call an den MCP-Server und gibt das Ergebnis zurück."""
        request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {
                "name": self.name,
                "arguments": arguments,
            },
        }

        try:
            async with httpx.AsyncClient(timeout=60) as client:
                resp = await client.post(
                    self.server_url,
                    json=request,
                    headers=self._headers(),
                )
                resp.raise_for_status()
                data = _parse_mcp_response(resp)

                # JSON-RPC Error prüfen
                if "error" in data:
                    return f"MCP-Fehler: {data['error'].get('message', 'Unbekannter Fehler')}"

                # Ergebnis extrahieren
                result = data.get("result", {})
                content = result.get("content", [])

                # Content kann Liste von {type, text} Objekten sein
                if isinstance(content, list):
                    parts = []
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "text":
                            parts.append(item.get("text", ""))
                        elif isinstance(item, str):
                            parts.append(item)
                    return "\n".join(parts) if parts else str(result)

                return str(result)

        except httpx.TimeoutException:
            return f"Timeout beim MCP-Tool {self.name}"
        except Exception as e:
            return f"Fehler bei MCP-Tool {self.name}: {str(e)}"


class MCPClient:
    """
    Client für einen MCP-Server.
    Listet verfügbare Tools und erstellt MCPTool-Instanzen.
    """

    def __init__(self, server_url: str, api_key: Optional[str] = None):
        self.server_url = server_url.rstrip("/")
        self.api_key = api_key

    def _headers(self) -> Dict[str, str]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return headers

    async def initialize(self) -> bool:
        """Sendet initialize-Handshake an den MCP-Server."""
        request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "NexusChat", "version": "1.0.0"},
            },
        }
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(
                    self.server_url,
                    json=request,
                    headers=self._headers(),
                )
                return resp.status_code == 200
        except Exception:
            return False

    async def list_tools(self) -> List[MCPTool]:
        """Gibt alle verfügbaren Tools des MCP-Servers zurück."""
        request = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {},
        }
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(
                    self.server_url,
                    json=request,
                    headers=self._headers(),
                )
                resp.raise_for_status()
                data = _parse_mcp_response(resp)

                tools_data = data.get("result", {}).get("tools", [])
                return [
                    MCPTool(tool_def, self.server_url, self.api_key)
                    for tool_def in tools_data
                ]

        except Exception as e:
            logger.error(f"Fehler beim Abrufen von MCP-Tools von {self.server_url}: {e}")
            return []

    async def test_connection(self) -> bool:
        """Prüft ob der MCP-Server erreichbar und bereit ist."""
        return await self.initialize()
