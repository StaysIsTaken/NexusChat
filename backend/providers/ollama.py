"""
Ollama Provider – lokale Modelle via HTTP.

Standard-URL: http://localhost:11434
Keine API-Key nötig.
Unterstützt natives Tool-Calling (Function Calling) für kompatible Modelle.
"""

import json
import logging
import httpx
from typing import AsyncGenerator, Optional, List, Dict, Any

from .base import BaseProvider, ChatMessage

logger = logging.getLogger(__name__)

# Sentinel-Objekt: wenn der Generator diesen Dict yieldet, ist es ein Tool-Call
_TOOL_CALL_TYPE = "__native_tool_call__"


class OllamaProvider(BaseProvider):
    name = "ollama"
    display_name = "Ollama (Lokal)"

    def supports_native_tools(self) -> bool:
        return True

    def tools_to_native_format(self, tools: List[Any]) -> List[Dict[str, Any]]:
        """Konvertiert BaseTool-Objekte ins Ollama/OpenAI Function-Calling Format."""
        result = []
        for t in tools:
            props = {}
            required = []
            for pname, p in t.parameters.items():
                props[pname] = {"type": p.type, "description": p.description}
                if p.required:
                    required.append(pname)

            result.append({
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": t.description,
                    "parameters": {
                        "type": "object",
                        "properties": props,
                        "required": required,
                    },
                },
            })
        return result

    async def chat(
        self,
        messages: List[ChatMessage],
        model: str,
        system_prompt: Optional[str] = None,
        tools: Optional[List[Dict]] = None,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        """
        Streamt Chat-Antwort von Ollama /api/chat.

        Wenn tools übergeben werden, nutzt Ollama natives Function-Calling.
        Tool-Calls werden als Dict {"__type__": "__native_tool_call__", ...} geyieldet.
        Thinking-Inhalt (qwen3 etc.) wird als <think>...</think> geyieldet.
        """
        ollama_messages = []
        if system_prompt:
            ollama_messages.append({"role": "system", "content": system_prompt})

        for msg in messages:
            m: Dict[str, Any] = {"role": msg.role, "content": msg.content}
            if msg.tool_calls:
                m["tool_calls"] = msg.tool_calls
            ollama_messages.append(m)

        payload: Dict[str, Any] = {
            "model": model,
            "messages": ollama_messages,
            "stream": True,
        }
        if tools:
            payload["tools"] = tools

        url = f"{self.base_url}/api/chat"

        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream("POST", url, json=payload) as response:
                response.raise_for_status()

                in_think_block = False
                # Tool-Calls über alle Chunks sammeln (kommen bei streaming VOR done=True)
                collected_tool_calls: list = []

                async for line in response.aiter_lines():
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    msg = data.get("message", {})
                    thinking = msg.get("thinking", "")
                    content  = msg.get("content", "")
                    done     = data.get("done", False)

                    # Tool-Calls in jedem Chunk einsammeln (nicht nur done-Chunk)
                    chunk_tool_calls = msg.get("tool_calls", [])
                    if chunk_tool_calls:
                        collected_tool_calls.extend(chunk_tool_calls)
                        logger.info(f"Ollama tool_calls chunk: {chunk_tool_calls}")

                    # Thinking-Inhalt als <think> Block streamen
                    if thinking:
                        if not in_think_block:
                            yield "<think>"
                            in_think_block = True
                        yield thinking.replace("</think>", "</ think>")

                    # Normalen Content streamen
                    if content:
                        if in_think_block:
                            yield "</think>"
                            in_think_block = False
                        yield content

                    if done:
                        # Think-Block schließen falls noch offen
                        if in_think_block:
                            yield "</think>"

                        # Auch im done-Chunk nochmal prüfen (manche Ollama-Versionen)
                        done_tool_calls = msg.get("tool_calls", [])
                        if done_tool_calls:
                            collected_tool_calls.extend(done_tool_calls)

                        logger.info(f"Ollama done – gesammelte tool_calls: {collected_tool_calls}")

                        for tc in collected_tool_calls:
                            fn = tc.get("function", {})
                            name = fn.get("name", "")
                            args = fn.get("arguments", {})
                            if isinstance(args, str):
                                try:
                                    args = json.loads(args)
                                except json.JSONDecodeError:
                                    args = {}
                            if name:
                                yield json.dumps({
                                    "__type__": _TOOL_CALL_TYPE,
                                    "name": name,
                                    "arguments": args,
                                })
                        break

    async def list_models(self) -> List[str]:
        """Gibt alle lokal installierten Modelle zurück."""
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(f"{self.base_url}/api/tags")
                resp.raise_for_status()
                data = resp.json()
                return [m["name"] for m in data.get("models", [])]
        except Exception:
            return []

    async def test_connection(self) -> bool:
        """Prüft ob Ollama läuft."""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(f"{self.base_url}/api/tags")
                return resp.status_code == 200
        except Exception:
            return False
