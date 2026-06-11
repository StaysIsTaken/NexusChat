"""
Anthropic Provider – Claude-Modelle via Anthropic API.

Standard-URL: https://api.anthropic.com
API-Key erforderlich.
Besonderheit: System-Prompt ist ein separates Feld, nicht in messages[].
"""

import json
import httpx
from typing import AsyncGenerator, Optional, List, Dict, Any

from .base import BaseProvider, ChatMessage


class AnthropicProvider(BaseProvider):
    name = "anthropic"
    display_name = "Anthropic (Claude)"

    DEFAULT_BASE_URL = "https://api.anthropic.com"
    API_VERSION = "2023-06-01"

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        if not self.base_url:
            self.base_url = self.DEFAULT_BASE_URL

    def _get_headers(self) -> Dict[str, str]:
        """Anthropic nutzt x-api-key statt Bearer-Auth."""
        headers = {
            "Content-Type": "application/json",
            "x-api-key": self.api_key,
            "anthropic-version": self.API_VERSION,
        }
        headers.update(self.custom_headers)
        return headers

    async def chat(
        self,
        messages: List[ChatMessage],
        model: str,
        system_prompt: Optional[str] = None,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        """Streamt Chat-Antwort via Anthropic /v1/messages."""

        # Anthropic erwartet alternierend user/assistant Nachrichten
        # System-Nachrichten aus dem Verlauf herausfiltern
        anthropic_messages = []
        for msg in messages:
            if msg.role == "system":
                continue
            anthropic_messages.append({"role": msg.role, "content": msg.content})

        # Leere Nachrichten-Liste abfangen
        if not anthropic_messages:
            return

        payload: Dict[str, Any] = {
            "model": model,
            "messages": anthropic_messages,
            "max_tokens": 8192,
            "stream": True,
        }

        # System-Prompt als Top-Level-Feld (Anthropic-spezifisch)
        if system_prompt:
            payload["system"] = system_prompt

        url = f"{self.base_url}/v1/messages"
        headers = self._get_headers()

        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream("POST", url, json=payload, headers=headers) as resp:
                resp.raise_for_status()

                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    raw = line[6:]
                    if raw in ("[DONE]", ""):
                        continue
                    try:
                        data = json.loads(raw)
                        event_type = data.get("type", "")

                        # content_block_delta enthält die eigentlichen Tokens
                        if event_type == "content_block_delta":
                            delta = data.get("delta", {})
                            if delta.get("type") == "text_delta":
                                text = delta.get("text", "")
                                if text:
                                    yield text

                        elif event_type == "message_stop":
                            break

                    except (json.JSONDecodeError, KeyError):
                        continue

    async def list_models(self) -> List[str]:
        """Bekannte Claude-Modelle – Anthropic hat keine /models Endpoint."""
        return [
            "claude-sonnet-4-6",
            "claude-opus-4-8",
            "claude-haiku-4-5-20251001",
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-opus-20240229",
        ]

    async def test_connection(self) -> bool:
        """Testet mit einem Minimal-Request ob der API-Key gültig ist."""
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                payload = {
                    "model": "claude-haiku-4-5-20251001",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "max_tokens": 1,
                }
                resp = await client.post(
                    f"{self.base_url}/v1/messages",
                    json=payload,
                    headers=self._get_headers(),
                )
                return resp.status_code in (200, 400)  # 400 = Auth OK aber ungültige Anfrage
        except Exception:
            return False
