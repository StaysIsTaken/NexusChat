"""
REST-API als Tool – bindet beliebige REST-APIs als Tool ein.

Konfiguration (JSON in der Datenbank):
{
  "name": "Wetter API",
  "type": "rest",
  "baseUrl": "https://api.example.com",
  "apiKey": "optional",
  "endpoints": [
    {
      "name": "get_weather",
      "method": "GET",
      "path": "/current",
      "description": "Gibt aktuelles Wetter zurück",
      "parameters": {
        "city": {"type": "string", "description": "Stadtname", "required": true}
      }
    }
  ]
}
"""

import json
import httpx
from typing import Any, Dict, List, Optional

from .base import BaseTool, ToolParameter, ToolInfo


class RestEndpointTool(BaseTool):
    """
    Repräsentiert einen einzelnen REST-API-Endpunkt als Tool.
    Für jede konfigurierte endpoint wird eine Instanz dieser Klasse erstellt.
    """

    def __init__(
        self,
        endpoint_config: Dict[str, Any],
        base_url: str,
        api_key: Optional[str] = None,
        global_headers: Optional[Dict[str, str]] = None,
    ):
        self.endpoint_config = endpoint_config
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.global_headers = global_headers or {}

        # Pflichtfelder aus der Konfiguration übernehmen
        self.name = endpoint_config["name"]
        self.description = endpoint_config.get("description", f"{endpoint_config['name']} endpoint")
        self.method = endpoint_config.get("method", "GET").upper()
        self.path = endpoint_config.get("path", "/")

        # Parameter-Schema aufbauen
        self.parameters = {
            pname: ToolParameter(
                type=p.get("type", "string"),
                description=p.get("description", pname),
                required=p.get("required", True),
            )
            for pname, p in endpoint_config.get("parameters", {}).items()
        }

    def _build_headers(self) -> Dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        headers.update(self.global_headers)
        return headers

    async def execute(self, arguments: Dict[str, Any]) -> str:
        """Führt den REST-API-Aufruf aus und gibt das Ergebnis zurück."""
        url = f"{self.base_url}{self.path}"
        headers = self._build_headers()

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                if self.method in ("GET", "DELETE"):
                    # Parameter als Query-String
                    resp = await client.request(
                        self.method, url, params=arguments, headers=headers
                    )
                else:
                    # Parameter als JSON-Body
                    resp = await client.request(
                        self.method, url, json=arguments, headers=headers
                    )

                # Antwort als Text zurückgeben (JSON falls möglich)
                try:
                    result = resp.json()
                    return json.dumps(result, ensure_ascii=False, indent=2)
                except Exception:
                    return resp.text

        except httpx.TimeoutException:
            return f"Fehler: Timeout beim Aufruf von {url}"
        except Exception as e:
            return f"Fehler beim REST-API-Aufruf: {str(e)}"


def create_rest_tools(server_config: Dict[str, Any]) -> List[RestEndpointTool]:
    """
    Erstellt Tool-Instanzen aus einer REST-Server-Konfiguration.
    Eine Instanz pro konfiguriertem Endpunkt.
    """
    tools = []
    base_url = server_config.get("url", "")
    api_key = server_config.get("api_key", "")
    config = server_config.get("config", {})
    global_headers = config.get("headers", {})

    for endpoint in config.get("endpoints", []):
        tool = RestEndpointTool(
            endpoint_config=endpoint,
            base_url=base_url,
            api_key=api_key,
            global_headers=global_headers,
        )
        tools.append(tool)

    return tools
