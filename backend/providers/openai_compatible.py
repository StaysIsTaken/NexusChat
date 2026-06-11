"""
OpenAI-kompatibler Provider – funktioniert mit jeder API die das OpenAI-Format implementiert:
- LM Studio (http://localhost:1234/v1)
- vLLM
- LocalAI
- Groq (https://api.groq.com/openai/v1)
- Together AI (https://api.together.xyz/v1)
- Fireworks AI
- ...und viele mehr

Einfach Base-URL auf den jeweiligen Endpunkt setzen.
"""

import json
import httpx
from typing import AsyncGenerator, Optional, List, Dict, Any

from .base import BaseProvider, ChatMessage


class OpenAICompatibleProvider(BaseProvider):
    name = "openai_compatible"
    display_name = "OpenAI-Kompatibel (Universell)"

    async def chat(
        self,
        messages: List[ChatMessage],
        model: str,
        system_prompt: Optional[str] = None,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        """Streamt via OpenAI-kompatiblem /chat/completions Endpunkt."""

        compat_messages = []
        if system_prompt:
            compat_messages.append({"role": "system", "content": system_prompt})

        for msg in messages:
            if msg.role == "system":
                continue
            compat_messages.append({"role": msg.role, "content": msg.content})

        payload = {
            "model": model,
            "messages": compat_messages,
            "stream": True,
        }

        # Viele lokale Server brauchen kein max_tokens, andere schon
        if kwargs.get("max_tokens"):
            payload["max_tokens"] = kwargs["max_tokens"]

        url = f"{self.base_url}/chat/completions"
        headers = self._get_headers()

        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream("POST", url, json=payload, headers=headers) as resp:
                resp.raise_for_status()

                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    raw = line[6:]
                    if raw == "[DONE]":
                        break
                    try:
                        data = json.loads(raw)
                        # Standard OpenAI-Format
                        choices = data.get("choices", [])
                        if not choices:
                            continue
                        delta = choices[0].get("delta", {})
                        content = delta.get("content", "")
                        if content:
                            yield content
                    except (json.JSONDecodeError, KeyError, IndexError):
                        continue

    async def list_models(self) -> List[str]:
        """Versucht Modelle via /models Endpunkt abzurufen."""
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(
                    f"{self.base_url}/models",
                    headers=self._get_headers(),
                )
                resp.raise_for_status()
                data = resp.json()
                models = data.get("data", [])
                return [m["id"] for m in models]
        except Exception:
            return []

    async def test_connection(self) -> bool:
        """Prüft ob der Endpunkt erreichbar ist."""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                # Erst /models versuchen, dann /chat/completions Endpunkt
                resp = await client.get(
                    f"{self.base_url}/models",
                    headers=self._get_headers(),
                )
                return resp.status_code in (200, 401, 403)
        except Exception:
            return False
