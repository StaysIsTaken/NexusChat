# NexusChat

Universelle, erweiterbare KI-Chat-Applikation mit Flutter (Desktop + Web) und selbst-hostbarem Python/FastAPI-Backend.

## Das Problem das gelöst wird

**Problem 1 – Tool-Calling:** Lokale Modelle unterstützen kein zuverlässiges Tool-Calling. NexusChat übernimmt Tool-Calling eigenständig im Backend – unabhängig vom Modell. Jedes Modell das Anweisungen folgen kann, kann Tools verwenden.

**Problem 2 – Erweiterbarkeit:** Bestehende Apps sind auf wenige fest eingebaute Provider beschränkt. NexusChat ist ein offenes Plugin-System – neue Provider und Tools als Python-Dateien hinzufügen, kein Core-Eingriff nötig.

## Schnellstart mit Docker

```bash
# Repository klonen / Ordner aufrufen
cd nexuschat

# Starten
docker-compose up --build

# Frontend: http://localhost:3000
# Backend API: http://localhost:8099
# API-Docs: http://localhost:8099/docs
```

## Lokale Entwicklung

### Backend
```powershell
cd backend
pip install -r requirements.txt
python -m uvicorn main:app --reload --port 8099
```

> **Hinweis:** `uvicorn` direkt aufzurufen funktioniert nur wenn Pythons `Scripts/`-Verzeichnis im PATH ist. `python -m uvicorn` funktioniert immer.

### Frontend (Desktop)
```bash
cd frontend
flutter pub get
flutter run -d windows   # oder -d linux / -d macos
```

### Frontend (Web)
```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 3000
```

## Provider konfigurieren

### Ollama (lokal)
1. [Ollama installieren](https://ollama.ai) und Modell laden: `ollama pull llama3.2`
2. In NexusChat: **Provider** → **Provider hinzufügen**
   - Typ: `Ollama (Lokal)`
   - URL: `http://localhost:11434` (oder Docker: `http://host.docker.internal:11434`)
   - Standard-Modell: `llama3.2`

### OpenAI
- Typ: `OpenAI (GPT)`
- API Key: dein OpenAI API Key
- Standard-Modell: `gpt-4o`

### Anthropic Claude
- Typ: `Anthropic (Claude)`
- API Key: dein Anthropic API Key
- Standard-Modell: `claude-sonnet-4-6`

### LM Studio / LocalAI / Groq / Together AI
- Typ: `OpenAI-Kompatibel`
- URL: jeweiligen Endpunkt (z.B. `http://localhost:1234/v1` für LM Studio)

## Tools hinzufügen

### MCP-Server
```json
Typ: MCP-Server
URL: http://mein-mcp-server:8080
```

### REST-API als Tool
```json
Typ: REST-API
URL: https://api.example.com
Konfiguration:
{
  "endpoints": [
    {
      "name": "get_weather",
      "method": "GET",
      "path": "/current",
      "description": "Aktuelles Wetter",
      "parameters": {
        "city": {"type": "string", "description": "Stadtname", "required": true}
      }
    }
  ]
}
```

## Plugins entwickeln

### Eigener Provider
```python
# plugins/providers/mein_provider.py
from providers.base import BaseProvider, ChatMessage
from typing import AsyncGenerator, Optional, List, Dict, Any

class MeinProvider(BaseProvider):
    name = "mein_provider"
    display_name = "Mein Provider"
    
    async def chat(self, messages, model, system_prompt=None, **kwargs):
        # Tokens yielden
        yield "Hallo "
        yield "Welt!"
    
    async def list_models(self):
        return ["modell-1", "modell-2"]
    
    async def test_connection(self):
        return True
```

Datei in `plugins/providers/` ablegen → Backend neu starten → fertig.

### Eigenes Tool
```python
# plugins/tools/mein_tool.py
from tools.base import BaseTool, ToolParameter
from typing import Any, Dict

class MeinTool(BaseTool):
    name = "mein_tool"
    description = "Was das Tool macht"
    parameters = {
        "eingabe": ToolParameter(type="string", description="Eingabe", required=True)
    }
    
    async def execute(self, arguments: Dict[str, Any]) -> str:
        return f"Ergebnis: {arguments['eingabe']}"
```

Datei in `plugins/tools/` ablegen → Backend neu starten → fertig.

## Projektstruktur

```
nexuschat/
├── backend/
│   ├── main.py                 # FastAPI App
│   ├── models.py               # SQLite Datenmodelle
│   ├── core/
│   │   ├── tool_caller.py      # Modell-unabhängiges Tool-Calling ⭐
│   │   ├── mcp_client.py       # MCP Streamable HTTP Client
│   │   └── plugin_loader.py    # Automatisches Plugin-Laden
│   ├── providers/              # KI-Provider Implementierungen
│   │   ├── base.py             # BaseProvider Interface
│   │   ├── ollama.py
│   │   ├── openai_provider.py
│   │   ├── anthropic_provider.py
│   │   └── openai_compatible.py
│   ├── tools/                  # Tool Implementierungen
│   │   ├── base.py             # BaseTool Interface
│   │   └── rest_tool.py        # REST-API als Tool
│   └── api/                    # API Endpoints
│       ├── chat.py             # Chat + WebSocket Streaming
│       ├── providers.py
│       ├── tools.py
│       └── settings.py
├── frontend/
│   └── lib/
│       ├── main.dart           # App-Shell, Navigation
│       ├── models/models.dart  # Dart Datenmodelle
│       ├── services/
│       │   ├── api_service.dart
│       │   └── websocket_service.dart
│       ├── screens/
│       │   ├── chat_screen.dart       # Chat mit Streaming
│       │   ├── chat_list_screen.dart
│       │   ├── provider_screen.dart
│       │   └── tool_screen.dart
│       └── widgets/
│           ├── message_bubble.dart    # Markdown + Code
│           └── tool_call_widget.dart  # Tool-Call Anzeige
├── plugins/                    # Deine eigenen Plugins
│   ├── providers/              # Eigene Provider (Volume-gemountet)
│   └── tools/                  # Eigene Tools (Volume-gemountet)
└── docker-compose.yml
```

## WebSocket Event-Protokoll

Das Frontend kommuniziert mit dem Backend über WebSocket:

| Event | Bedeutung |
|-------|-----------|
| `{"type": "token", "content": "..."}` | Antwort-Token vom Modell |
| `{"type": "tool_start", "name": "...", "arguments": {...}}` | Tool wird aufgerufen |
| `{"type": "tool_end", "name": "...", "result": "..."}` | Tool-Ergebnis |
| `{"type": "done", "tool_calls": [...]}` | Fertig |
| `{"type": "error", "message": "..."}` | Fehler |

## Lizenz

MIT
