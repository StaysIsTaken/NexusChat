"""
Beispiel: Eigener Provider als Plugin.

Diese Datei demonstriert wie ein eigener Provider erstellt wird.
Einfach diese Datei als Vorlage nehmen, anpassen und in plugins/providers/ ablegen.
Beim nächsten Backend-Start wird er automatisch erkannt.

Dieses Beispiel implementiert einen Echo-Provider der jede Anfrage widerspiegelt
(nützlich für Tests ohne echtes Modell).
"""

import sys
import os

# Wichtig: Backend-Pfad zum sys.path hinzufügen damit imports funktionieren
# (wird automatisch vom PluginLoader erledigt)
from providers.base import BaseProvider, ChatMessage
from typing import AsyncGenerator, Optional, List, Dict, Any


class EchoProvider(BaseProvider):
    """
    Echo-Provider – gibt die letzte Nutzernachricht gespiegelt zurück.
    Gut für Tests und als Vorlage für neue Provider.
    """

    name = "echo"
    display_name = "Echo (Test-Provider)"

    async def chat(
        self,
        messages: List[ChatMessage],
        model: str,
        system_prompt: Optional[str] = None,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        # Letzte Nutzernachricht finden
        user_content = "Keine Nachricht"
        for msg in reversed(messages):
            if msg.role == "user":
                user_content = msg.content
                break

        # Antwort Token für Token yielden (simuliert Streaming)
        response = f"Echo [{model}]: {user_content}"
        for char in response:
            yield char

    async def list_models(self) -> List[str]:
        return ["echo-v1", "echo-v2"]

    async def test_connection(self) -> bool:
        return True  # Echo ist immer verfügbar
