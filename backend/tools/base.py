"""
BaseTool – gemeinsames Interface für alle Tools/MCP-Server.

Um ein eigenes Tool hinzuzufügen:
1. Diese Datei importieren
2. Eine Klasse implementieren die BaseTool erweitert
3. Datei im tools/ Ordner ablegen → automatische Erkennung
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional
from pydantic import BaseModel


class ToolParameter(BaseModel):
    """Beschreibung eines einzelnen Tool-Parameters."""
    type: str               # "string", "integer", "boolean", "array", "object"
    description: str
    required: bool = True
    enum: Optional[List[Any]] = None   # Erlaubte Werte


class ToolInfo(BaseModel):
    """Vollständige Tool-Beschreibung für das Modell."""
    name: str
    description: str
    parameters: Dict[str, ToolParameter]

    def to_prompt_description(self) -> str:
        """Formatiert das Tool für die System-Prompt-Injektion."""
        params_text = "\n".join(
            f"  - {pname} ({p.type}{'*' if p.required else ''}): {p.description}"
            for pname, p in self.parameters.items()
        )
        return f"**{self.name}** – {self.description}\nParameter:\n{params_text}"

    def to_json_schema(self) -> Dict[str, Any]:
        """JSON-Schema-Format für OpenAI/Anthropic native Tool-Calling."""
        properties = {}
        required = []
        for pname, p in self.parameters.items():
            prop: Dict[str, Any] = {"type": p.type, "description": p.description}
            if p.enum:
                prop["enum"] = p.enum
            properties[pname] = prop
            if p.required:
                required.append(pname)
        return {
            "name": self.name,
            "description": self.description,
            "input_schema": {
                "type": "object",
                "properties": properties,
                "required": required,
            },
        }


class BaseTool(ABC):
    """
    Abstrakte Basisklasse für alle Tools.

    Neue Tools als Python-Datei im tools/ Ordner ablegen.
    Der PluginLoader erkennt alle Klassen die BaseTool erweitern.

    Beispiel-Implementierung: tools/rest_tool.py
    """

    name: str = "base_tool"
    description: str = "Base Tool"
    parameters: Dict[str, ToolParameter] = {}
    requires_confirmation: bool = False  # True → Ausführung muss vom Nutzer bestätigt werden

    def get_info(self) -> ToolInfo:
        """Gibt die vollständige Tool-Beschreibung zurück."""
        return ToolInfo(
            name=self.name,
            description=self.description,
            parameters=self.parameters,
        )

    @abstractmethod
    async def execute(self, arguments: Dict[str, Any]) -> str:
        """
        Führt das Tool mit den gegebenen Argumenten aus.

        Args:
            arguments: Vom Modell extrahierte Parameter

        Returns:
            Ergebnis als String (wird ans Modell zurückgegeben)

        Niemals Exceptions werfen – Fehler als String zurückgeben:
        return f"Fehler: {str(e)}"
        """
        ...
