# NexusChat

Universelle, erweiterbare KI-Chat-Applikation mit Flutter (Desktop + Web) und selbst-hostbarem Python/FastAPI-Backend.

## Das Problem das gelöst wird

**Problem 1 – Tool-Calling:** NexusChat steuert Tool-Calling eigenständig im Backend. Zwei Pfade: **nativ** über die Function-Calling-API des Providers (z.B. Ollama mit `llama3.2`) und als **Fallback** XML-Injektion in den System-Prompt für Modelle ohne native Unterstützung. Tool-Ausführung, Ergebnis-Rückführung und Mehrfach-Aufrufe übernimmt das Backend.

**Problem 2 – Erweiterbarkeit:** Bestehende Apps sind auf wenige fest eingebaute Provider beschränkt. NexusChat ist ein offenes Plugin-System – neue Provider und Tools als Python-Dateien hinzufügen, kein Core-Eingriff nötig.

## Benutzer & Rechte

NexusChat ist mehrbenutzerfähig mit JWT-basierter Authentifizierung:

- **Einmalige Einrichtung:** Solange kein Admin existiert, zeigt die App ein Setup-Formular. Der erste angelegte Account wird zum **Administrator**.
- **Admin** kann Provider und Tools anlegen/verbinden, Benutzer erstellen und ihnen gezielt einzelne Provider/Tools zuweisen.
- **Benutzer** sehen ausschließlich ihre eigenen Chats und nur die ihnen zugewiesenen Provider/Tools. Sie können selbst keine Provider/Tools anlegen.

Passwörter werden mit bcrypt gehasht, Tokens als JWT (HS256) signiert; das Secret wird beim ersten Start generiert und in der Datenbank gespeichert.

## Funktionen im Überblick

**Sicherheit**
- API-Keys von Providern/Tools werden verschlüsselt gespeichert (Fernet) und nie an den Client ausgeliefert
- Login-Rate-Limiting gegen Brute-Force
- Erzwungener Passwortwechsel für neu angelegte Konten + Self-Service-Passwortänderung
- DB-Backup-Download für den Admin

**Chat**
- Token-Streaming, Stop-Button (Teilantwort bleibt erhalten)
- Nachricht bearbeiten & Antwort neu generieren
- Kopieren pro Nachricht + Markdown-Export des ganzen Chats
- Code-Blöcke mit Syntax-Highlighting und Copy-Button
- Automatischer Chat-Titel per LLM
- Volltextsuche über alle Nachrichten
- Aufklappbare „Reasoning"-Blöcke (`<think>`) und Tool-Call-Anzeige

**Tools**
- Modell-unabhängiges Tool-Calling (nativ + XML-Fallback)
- Optionale **Ausführungsbestätigung** pro Tool-Server: der Nutzer sieht vor der Ausführung genau, was getan werden soll, und bestätigt/lehnt ab

**Admin**
- Benutzerverwaltung mit gezielter Provider-/Tool-Zuweisung
- Health-Dashboard: zeigt live, welche Provider/Tools erreichbar sind

## Schnellstart mit Docker (Full-Stack)

Startet Backend **und** Web-Frontend zusammen:

```bash
cd nexuschat
docker compose up --build

# Frontend:    http://localhost:3000   → beim ersten Aufruf Admin einrichten
# Backend API: http://localhost:8099
# API-Docs:    http://localhost:8099/docs
```

> **Nur das Backend** (z.B. wenn das Frontend als native Desktop-App läuft):
> ```bash
> cd nexuschat/backend
> docker compose up --build -d
> ```
> Siehe Abschnitt [Deployment](#deployment).

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

## Deployment

### Variante A – Full-Stack (Web-Frontend + Backend)
```bash
cd nexuschat
docker compose up --build -d
```
Frontend auf Port `3000`, Backend auf `8099`. Das nginx im Frontend-Container proxied `/api` und `/ws` zum Backend.

### Variante B – Nur Backend im Container + native Desktop-App
Server (z.B. via Portainer oder direkt):
```bash
cd nexuschat/backend
docker compose up --build -d        # Backend auf Port 8099
```
Native Windows-App bauen:
```bash
cd nexuschat/frontend
flutter build windows --release
# Ergebnis: build/windows/x64/runner/Release/  (gesamten Ordner weitergeben)
```
Die App fragt beim ersten Start nach Login/Setup. Die Backend-URL (`http://<server-ip>:8099`)
wird in den App-Einstellungen hinterlegt und gespeichert.

### Portainer (aus GitHub-Repo)
1. **Stacks → Add stack → Repository**
2. Repository-URL eintragen, Branch z.B. `refs/heads/main`
3. **Compose path:** `nexuschat/backend/docker-compose.yml` (nur Backend) oder `nexuschat/docker-compose.yml` (Full-Stack)
4. **Deploy** – Portainer klont, baut das Image und startet den Container.

### Hinweise
- **Daten bleiben erhalten:** Die SQLite-DB liegt im Named Volume `nexuschat-data`. Beim ersten Start ist sie leer → Admin einrichten, Provider/Tools anlegen.
- **Ollama/MCP-Erreichbarkeit:** Läuft Ollama auf demselben Host wie der Container, nutze `http://host.docker.internal:11434` statt `localhost`. Bei einer anderen Maschine die LAN-IP eintragen.
- Die DB (`backend/data/`) ist via `.gitignore`/`.dockerignore` ausgeschlossen und landet nie im Image oder Repo.

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
│   ├── models.py               # SQLite Datenmodelle (User, Chats, Provider, Tools …)
│   ├── Dockerfile
│   ├── docker-compose.yml      # Nur-Backend-Deployment
│   ├── core/
│   │   ├── tool_caller.py      # Tool-Calling: nativ (Ollama) + XML-Fallback ⭐
│   │   ├── auth.py             # JWT, bcrypt, Zugriffskontrolle
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
│       ├── auth.py             # Setup / Login / Profil
│       ├── users.py            # Benutzerverwaltung (Admin)
│       ├── chat.py             # Chat + WebSocket Streaming
│       ├── providers.py
│       ├── tools.py
│       └── settings.py
├── frontend/
│   ├── Dockerfile              # Web-Build + nginx
│   ├── nginx.conf
│   └── lib/
│       ├── main.dart           # App-Shell, Auth-Gate, rollenbasierte Navigation
│       ├── models/models.dart  # Dart Datenmodelle (inkl. AppUser)
│       ├── services/
│       │   ├── api_service.dart      # REST inkl. Token-Header
│       │   └── websocket_service.dart # Stream + persistenter Socket-Manager
│       ├── screens/
│       │   ├── auth_screen.dart          # Login / Admin-Setup
│       │   ├── user_management_screen.dart # Benutzer + Zuweisungen (Admin)
│       │   ├── chat_screen.dart          # Chat mit Streaming
│       │   ├── chat_list_screen.dart
│       │   ├── provider_screen.dart
│       │   └── tool_screen.dart
│       └── widgets/
│           ├── message_bubble.dart    # Markdown + Code + Reasoning-Block
│           └── tool_call_widget.dart  # Tool-Call Anzeige
├── plugins/                    # Deine eigenen Plugins
│   ├── providers/              # Eigene Provider (Volume-gemountet)
│   └── tools/                  # Eigene Tools (Volume-gemountet)
├── docker-compose.yml          # Full-Stack-Deployment
└── README.md
```

## API-Überblick (Auth)

| Methode & Pfad | Zweck |
|----------------|-------|
| `GET /api/auth/status` | Muss noch ein Admin eingerichtet werden? |
| `POST /api/auth/setup` | Einmalige Admin-Registrierung |
| `POST /api/auth/login` | Anmeldung → JWT |
| `GET /api/auth/me` | Aktueller Nutzer |
| `GET/POST/DELETE /api/users` | Benutzerverwaltung (nur Admin) |
| `PUT /api/users/{id}/providers` · `/tools` | Provider/Tools zuweisen (nur Admin) |

REST-Aufrufe authentifizieren sich per `Authorization: Bearer <token>`.

## WebSocket Event-Protokoll

Verbindung: `ws://<host>/ws/chat/{chat_id}?token=<jwt>` — der Token wird als Query-Parameter übergeben (WebSockets können keine Auth-Header setzen).

| Event | Bedeutung |
|-------|-----------|
| `{"type": "token", "content": "..."}` | Antwort-Token vom Modell |
| `{"type": "tool_start", "name": "...", "arguments": {...}}` | Tool wird aufgerufen |
| `{"type": "tool_end", "name": "...", "result": "..."}` | Tool-Ergebnis |
| `{"type": "done", "tool_calls": [...]}` | Fertig |
| `{"type": "error", "message": "..."}` | Fehler |

## Lizenz

MIT
