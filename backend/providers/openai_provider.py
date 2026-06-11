"""
OpenAI Provider – OpenAI API (GPT-Modelle).

Standard-URL: https://api.openai.com/v1
API-Key erforderlich.
"""

import json
import httpx
from typing import AsyncGenerator, Optional, List, Dict, Any

from .base import BaseProvider, ChatMessage


class OpenAIProvider(BaseProvider):
    name = "openai"
    display_name = "OpenAI (GPT)"

    DEFAULT_BASE_URL = "https://api.openai.com/v1"

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        # Fallback auf Standard-URL
        if not self.base_url:
            self.base_url = self.DEFAULT_BASE_URL

    async def chat(
        self,
        messages: List[ChatMessage],
        model: str,
        system_prompt: Optional[str] = None,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        """Streamt Chat-Antwort via OpenAI /v1/chat/completions."""

        openai_messages = []

        # System-Prompt als erste Nachricht
        if system_prompt:
            openai_messages.append({"role": "system", "content": system_prompt})

        for msg in messages:
            # System-Nachrichten aus dem Verlauf überspringen (bereits oben gesetzt)
            if msg.role == "system":
                continue
            openai_messages.append({"role": msg.role, "content": msg.content})

        payload = {
            "model": model,
            "messages": openai_messages,
            "stream": True,
        }

        url = f"{self.base_url}/chat/completions"
        headers = self._get_headers()

        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream("POST", url, json=payload, headers=headers) as resp:
                resp.raise_for_status()

                async for line in resp.aiter_lines():
                    # OpenAI SSE-Format: "data: {...}" oder "data: [DONE]"
                    if not line.startswith("data: "):
                        continue
                    raw = line[6:]
                    if raw == "[DONE]":
                        break
                    try:
                        data = json.loads(raw)
                        delta = data["choices"][0]["delta"]
                        content = delta.get("content", "")
                        if content:
                            yield content
                    except (json.JSONDecodeError, KeyError, IndexError):
                        continue

    async def list_models(self) -> List[str]:
        """Gibt verfügbare Modelle aus der OpenAI API zurück."""
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(
                    f"{self.base_url}/models",
                    headers=self._get_headers(),
                )
                resp.raise_for_status()
                data = resp.json()
                models = [m["id"] for m in data.get("data", [])]
                # Nur Chat-Modelle zeigen
                chat_models = [m for m in models if "gpt" in m.lower() or "o1" in m.lower()]
                return sorted(chat_models)
        except Exception:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]

    async def test_connection(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(
                    f"{self.base_url}/models",
                    headers=self._get_headers(),
                )
                return resp.status_code == 200
        except Exception:
            return False
