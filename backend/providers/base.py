"""
BaseProvider – gemeinsames Interface für alle KI-Provider.

Um einen neuen Provider hinzuzufügen:
1. Diese Datei importieren
2. Eine Klasse implementieren die BaseProvider erweitert
3. Die Datei im providers/ Ordner ablegen
4. Der PluginLoader erkennt sie automatisch beim Start
"""

from abc import ABC, abstractmethod
from typing import AsyncGenerator, Optional, List, Dict, Any
from pydantic import BaseModel


class ChatMessage(BaseModel):
    """Einheitliches Nachrichten-Format für alle Provider."""
    role: str          # "user", "assistant", "system", "tool"
    content: str
    name: Optional[str] = None       # Für Tool-Messages (Tool-Name)
    tool_calls: Optional[List[Dict[str, Any]]] = None  # Für native Tool-Call-Antworten


class ToolDefinition(BaseModel):
    """Beschreibung eines Tools, die dem Modell übergeben wird."""
    name: str
    description: str
    parameters: Dict[str, Any]  # JSON-Schema der Parameter


class BaseProvider(ABC):
    """
    Abstrakte Basisklasse für alle KI-Provider.

    Jeder Provider muss:
    - name: eindeutiger Bezeichner (z.B. "ollama", "openai")
    - display_name: Anzeigename in der UI
    - chat(): Streaming-Chat implementieren
    - list_models(): Verfügbare Modelle zurückgeben
    - test_connection(): Erreichbarkeit prüfen

    Beispiel-Implementierung: providers/ollama.py
    """

    # Klassenattribute – in der Unterklasse überschreiben
    name: str = "base"
    display_name: str = "Base Provider"

    def __init__(self, config: Dict[str, Any]):
        """
        config enthält Provider-Einstellungen aus der Datenbank:
        - base_url: API-Endpunkt
        - api_key: API-Schlüssel (optional)
        - custom_headers: Zusätzliche HTTP-Header
        """
        self.config = config
        self.base_url = config.get("base_url", "").rstrip("/")
        self.api_key = config.get("api_key", "")
        self.custom_headers = config.get("custom_headers", {})

    def _get_headers(self) -> Dict[str, str]:
        """Baut die HTTP-Header inkl. Auth und Custom-Headers zusammen."""
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        headers.update(self.custom_headers)
        return headers

    def supports_native_tools(self) -> bool:
        """True wenn dieser Provider natives Function-Calling unterstützt."""
        return False

    def tools_to_native_format(self, tools: List[Any]) -> List[Dict[str, Any]]:
        """Konvertiert BaseTool-Liste ins provider-spezifische Format."""
        return []

    @abstractmethod
    async def chat(
        self,
        messages: List[ChatMessage],
        model: str,
        system_prompt: Optional[str] = None,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        """
        Sendet Nachrichten an das Modell und streamt die Antwort Token für Token.

        Args:
            messages: Bisheriger Gesprächsverlauf
            model: Modell-ID (z.B. "llama3.2", "gpt-4o")
            system_prompt: Optionaler System-Prompt (überschreibt Chat-Standard)

        Yields:
            Einzelne Text-Tokens der Antwort
        """
        ...

    @abstractmethod
    async def list_models(self) -> List[str]:
        """
        Gibt alle verfügbaren Modell-IDs zurück.
        Bei Fehler leere Liste zurückgeben, nicht werfen.
        """
        ...

    @abstractmethod
    async def test_connection(self) -> bool:
        """
        Prüft ob der Provider erreichbar ist.
        True = verbunden, False = nicht erreichbar.
        """
        ...
