"""
ToolCaller – modell-unabhängiges Tool-Calling.

Dies ist die Kernkomponente die NexusChat von anderen KI-Frontends unterscheidet.

Funktionsweise:
1. Tool-Beschreibungen werden in den System-Prompt injiziert
2. Das LLM schreibt <tool_call>{"name": "...", "arguments": {...}}</tool_call>
3. Backend erkennt und parst diese Tags
4. Tool wird ausgeführt
5. Ergebnis wird ans LLM zurückgegeben
6. Schleife bis keine Tool-Aufrufe mehr

Dadurch funktioniert Tool-Calling mit JEDEM Modell – auch solchen ohne
natives Tool-Calling (z.B. kleine lokale Modelle).

WebSocket-Event-Protokoll:
  {"type": "token",       "content": "..."}    – Antwort-Token vom Modell
  {"type": "tool_start",  "name": "...", "arguments": {...}}
  {"type": "tool_end",    "name": "...", "result": "..."}
  {"type": "done",        "tool_calls": [...]}  – Fertig, Tool-Aufrufe als Zusammenfassung
  {"type": "error",       "message": "..."}
"""

import json
import logging
import re
from typing import Any, AsyncGenerator, Dict, List, Optional

from providers.base import BaseProvider, ChatMessage
from tools.base import BaseTool, ToolInfo

logger = logging.getLogger(__name__)

# Maximale Anzahl Tool-Calls pro Anfrage (Schutz vor Endlosschleifen)
MAX_TOOL_ITERATIONS = 10

# Regex zum Erkennen von Tool-Aufrufen in der Modell-Antwort
# Format: <tool_call>{"name": "...", "arguments": {...}}</tool_call>
TOOL_CALL_RE = re.compile(
    r"<tool_call>\s*(.*?)\s*</tool_call>",
    re.DOTALL | re.IGNORECASE,
)

# Entfernt <think>...</think> und <tool_call>...</tool_call> Blöcke aus dem Text
_STRIP_RE = re.compile(
    r"<(think|tool_call)>.*?</(think|tool_call)>",
    re.DOTALL | re.IGNORECASE,
)

def _visible_response(text: str) -> str:
    """Gibt den für den Nutzer sichtbaren Teil der Modell-Antwort zurück."""
    return _STRIP_RE.sub("", text).strip()


def _sanitize_tool_args(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Bereinigt Tool-Argumente vor der Ausführung.
    Bekannte Modell-Quirks:
    - llama3.2: übergibt Parameter-Schema als Wert: {"type":"string","description":"echter wert"}
    - llama3.2: wrapet String-Wert in geschweifte Klammern: {"echter wert"}
    """
    result = {}
    for k, v in args.items():
        if isinstance(v, str):
            s = v.strip()
            # Versuche JSON zu parsen – manche Modelle übergeben Objekte als String
            try:
                parsed = json.loads(s)
                if isinstance(parsed, dict):
                    # Modell hat Parameter-Schema übergeben: {"type":"string","description":"wert"}
                    # → echten Wert aus "description" extrahieren
                    if "type" in parsed and "description" in parsed:
                        v = str(parsed["description"])
                    # Einzelwert-Dict: {"key": "wert"} → "wert"
                    elif len(parsed) == 1:
                        v = str(list(parsed.values())[0])
            except (json.JSONDecodeError, TypeError):
                # Kein gültiges JSON – direkte String-Muster prüfen
                if s.startswith('{"') and s.endswith('"}'):
                    v = s[2:-2]
                elif s.startswith("{'") and s.endswith("'}"):
                    v = s[2:-2]
        result[k] = v
    return result


TOOL_SYSTEM_PROMPT_TEMPLATE = """
## Verfügbare Tools

Du hast Zugriff auf folgende Tools. Nutze sie wenn sie zur Beantwortung der Anfrage nötig sind.

Um ein Tool aufzurufen, schreibe diesen XML-Block in deine Antwort:

<tool_call>
{{"name": "TOOL_NAME", "arguments": {{"parameter1": "wert1", "parameter2": "wert2"}}}}
</tool_call>

Das System erkennt diesen Block automatisch, führt das Tool aus und schickt das Ergebnis zurück.
Danach kannst du weiter antworten und das Ergebnis dem Nutzer erklären.

Regeln:
- Rufe nur Tools auf wenn nötig
- Pro Antwort maximal ein Tool-Aufruf
- Nach dem Tool-Aufruf erhältst du das Ergebnis als nächste Nachricht

### Verfügbare Tools:

{tool_descriptions}
"""


class ToolCaller:
    """
    Orchestriert Tool-Calling für einen einzelnen Chat-Turn.

    Verwendung:
        tools = await load_active_tools(active_tool_ids)
        caller = ToolCaller(tools)
        async for event in caller.run(messages, provider, model, system_prompt):
            await websocket.send_json(event)
    """

    def __init__(self, tools: List[BaseTool]):
        self.tools: Dict[str, BaseTool] = {t.name: t for t in tools}

    def _build_tool_system_prompt(self) -> Optional[str]:
        """Erstellt den Tool-Beschreibungs-Block für den System-Prompt."""
        if not self.tools:
            return None
        descriptions = "\n\n".join(
            t.get_info().to_prompt_description() for t in self.tools.values()
        )
        return TOOL_SYSTEM_PROMPT_TEMPLATE.format(tool_descriptions=descriptions)

    def _extract_tool_calls(self, text: str) -> List[Dict[str, Any]]:
        """
        Parst <tool_call>-Blöcke aus dem gesamten Text inkl. <think>-Blöcken.

        qwen3 und andere Thinking-Modelle schreiben Tool-Aufrufe oft innerhalb ihrer
        <think>-Blöcke. Diese werden trotzdem ausgeführt – das Modell erhält das echte
        Ergebnis im nächsten Turn und antwortet dann korrekt.
        """
        calls = []
        for match in TOOL_CALL_RE.finditer(text):
            raw = match.group(1).strip()
            try:
                data = json.loads(raw)
                name = data.get("name", "")
                args = data.get("arguments", {})
                if name:
                    calls.append({"name": name, "arguments": args})
            except json.JSONDecodeError as e:
                logger.warning(f"Ungültiger Tool-Call JSON: {raw[:100]} – {e}")
        return calls

    def _build_messages_for_provider(
        self,
        conversation: List[Dict[str, str]],
        system_prompt: Optional[str],
    ) -> tuple[List[ChatMessage], Optional[str]]:
        """
        Bereitet die Nachrichten für den Provider vor.
        Kombiniert Nutzer-System-Prompt mit Tool-Beschreibungen.
        """
        tool_prompt = self._build_tool_system_prompt()

        # System-Prompts zusammenführen
        full_system = ""
        if system_prompt:
            full_system += system_prompt.strip()
        if tool_prompt:
            if full_system:
                full_system += "\n\n---\n\n"
            full_system += tool_prompt.strip()

        messages = [
            ChatMessage(role=m["role"], content=m["content"])
            for m in conversation
        ]

        return messages, full_system or None

    async def run(
        self,
        conversation: List[Dict[str, str]],
        provider: BaseProvider,
        model: str,
        system_prompt: Optional[str] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Führt einen vollständigen Chat-Turn durch inkl. Tool-Calling-Schleife.

        Zwei Pfade:
        - Nativ: Provider unterstützt Function-Calling → Tools als API-Parameter
        - XML:   Fallback → Tool-Beschreibungen in System-Prompt injizieren
        """
        use_native = provider.supports_native_tools() and bool(self.tools)

        if use_native:
            async for event in self._run_native(conversation, provider, model, system_prompt):
                yield event
        else:
            async for event in self._run_xml(conversation, provider, model, system_prompt):
                yield event

    async def _run_native(
        self,
        conversation: List[Dict[str, Any]],
        provider: BaseProvider,
        model: str,
        system_prompt: Optional[str],
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Natives Tool-Calling: Tools werden als API-Parameter übergeben.
        Zuverlässig mit Modellen die Function-Calling unterstützen (Ollama, OpenAI…).
        """
        from providers.ollama import _TOOL_CALL_TYPE

        native_tools = provider.tools_to_native_format(list(self.tools.values()))
        current_conversation = list(conversation)
        all_tool_calls: List[Dict[str, Any]] = []
        iteration = 0

        while iteration < MAX_TOOL_ITERATIONS:
            iteration += 1

            # ChatMessage-Objekte bauen – tool_calls aus Dict übernehmen falls vorhanden
            messages = [
                ChatMessage(
                    role=m["role"],
                    content=m.get("content", ""),
                    tool_calls=m.get("tool_calls"),
                )
                for m in current_conversation
            ]
            full_system = system_prompt or None

            full_response = ""
            detected_native_calls: List[Dict[str, Any]] = []

            try:
                async for token in provider.chat(
                    messages, model=model, system_prompt=full_system, tools=native_tools
                ):
                    # Natives Tool-Call Signal (JSON-kodierter Sentinel-Dict)
                    try:
                        signal = json.loads(token)
                        if isinstance(signal, dict) and signal.get("__type__") == _TOOL_CALL_TYPE:
                            detected_native_calls.append({
                                "name": signal["name"],
                                "arguments": signal["arguments"],
                            })
                            continue
                    except (json.JSONDecodeError, TypeError):
                        pass

                    # Normales Token streamen
                    full_response += token
                    fl = full_response.lower()
                    in_tool = fl.count("<tool_call>") > fl.count("</tool_call>")
                    if not in_tool:
                        yield {"type": "token", "content": token}

            except Exception as e:
                logger.error(f"Provider-Fehler (nativ): {e}")
                yield {"type": "error", "message": f"Modell-Fehler: {str(e)}"}
                return

            if not detected_native_calls:
                yield {"type": "done", "tool_calls": all_tool_calls}
                return

            # Assistent-Nachricht MIT tool_calls ins Verlaufs-Dict schreiben
            # (Ollama braucht das für den nächsten Turn um zu wissen was aufgerufen wurde)
            assistant_tool_calls_ollama = [
                {"function": {"name": c["name"], "arguments": c["arguments"]}}
                for c in detected_native_calls
            ]
            current_conversation.append({
                "role": "assistant",
                "content": _visible_response(full_response),
                "tool_calls": assistant_tool_calls_ollama,
            })

            # Tools ausführen und Ergebnisse als role:tool zurückgeben
            for call in detected_native_calls:
                tool_name = call["name"]
                tool_args = _sanitize_tool_args(call["arguments"])

                yield {"type": "tool_start", "name": tool_name, "arguments": tool_args}

                tool = self.tools.get(tool_name)
                if tool is None:
                    result = f"Unbekanntes Tool: {tool_name}"
                    logger.warning(result)
                else:
                    try:
                        result = await tool.execute(tool_args)
                    except Exception as e:
                        result = f"Fehler bei Tool {tool_name}: {str(e)}"
                        logger.error(result)

                yield {"type": "tool_end", "name": tool_name, "result": result}
                all_tool_calls.append({**call, "result": result})

                current_conversation.append({
                    "role": "tool",
                    "content": str(result),
                })

        logger.warning(f"Maximale Tool-Iterations-Grenze ({MAX_TOOL_ITERATIONS}) erreicht")
        yield {"type": "error", "message": f"Maximale Tool-Aufrufe ({MAX_TOOL_ITERATIONS}) erreicht."}

    async def _run_xml(
        self,
        conversation: List[Dict[str, str]],
        provider: BaseProvider,
        model: str,
        system_prompt: Optional[str],
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        XML-basiertes Tool-Calling: Tool-Beschreibungen in System-Prompt injiziert.
        Fallback für Provider ohne natives Function-Calling.
        """
        current_conversation = list(conversation)
        all_tool_calls: List[Dict[str, Any]] = []
        iteration = 0

        while iteration < MAX_TOOL_ITERATIONS:
            iteration += 1

            messages, full_system = self._build_messages_for_provider(
                current_conversation, system_prompt
            )

            full_response = ""
            try:
                async for token in provider.chat(messages, model=model, system_prompt=full_system):
                    full_response += token
                    fl = full_response.lower()
                    in_tool = fl.count("<tool_call>") > fl.count("</tool_call>")
                    if not in_tool:
                        yield {"type": "token", "content": token}

            except Exception as e:
                logger.error(f"Provider-Fehler (XML): {e}")
                yield {"type": "error", "message": f"Modell-Fehler: {str(e)}"}
                return

            detected_calls = self._extract_tool_calls(full_response)

            if not detected_calls:
                yield {"type": "done", "tool_calls": all_tool_calls}
                return

            current_conversation.append({
                "role": "assistant",
                "content": _visible_response(full_response),
            })

            tool_results_text = ""
            for call in detected_calls:
                tool_name = call["name"]
                tool_args = _sanitize_tool_args(call["arguments"])

                yield {"type": "tool_start", "name": tool_name, "arguments": tool_args}

                tool = self.tools.get(tool_name)
                if tool is None:
                    result = f"Unbekanntes Tool: {tool_name}"
                    logger.warning(result)
                else:
                    try:
                        result = await tool.execute(tool_args)
                    except Exception as e:
                        result = f"Fehler bei Tool {tool_name}: {str(e)}"
                        logger.error(result)

                yield {"type": "tool_end", "name": tool_name, "result": result}
                all_tool_calls.append({**call, "result": result})

                tool_results_text += (
                    f"<tool_result>\n"
                    f"{{\"name\": \"{tool_name}\", "
                    f"\"result\": {json.dumps(result, ensure_ascii=False)}}}\n"
                    f"</tool_result>\n"
                )

            current_conversation.append({
                "role": "user",
                "content": tool_results_text.strip(),
            })

        logger.warning(f"Maximale Tool-Iterations-Grenze ({MAX_TOOL_ITERATIONS}) erreicht")
        yield {"type": "error", "message": f"Maximale Tool-Aufrufe ({MAX_TOOL_ITERATIONS}) erreicht."}


async def load_active_tools(
    active_tool_server_ids: List[str],
    all_tool_servers: List[Dict[str, Any]],
) -> List[BaseTool]:
    """
    Lädt alle aktiven Tools von den konfigurierten Tool-Servern.

    Unterstützte Typen:
    - mcp:    MCP-Server via HTTP
    - rest:   REST-API Endpunkte
    - custom: Python-Klassen aus dem tools/ Verzeichnis
    """
    from core.mcp_client import MCPClient
    from tools.rest_tool import create_rest_tools

    active_tools: List[BaseTool] = []
    active_ids_set = set(active_tool_server_ids)

    for server in all_tool_servers:
        if server["id"] not in active_ids_set:
            continue
        if not server.get("is_enabled", True):
            continue

        server_type = server.get("type", "")

        if server_type == "mcp":
            client = MCPClient(
                server_url=server.get("url", ""),
                api_key=server.get("api_key"),
            )
            mcp_tools = await client.list_tools()
            active_tools.extend(mcp_tools)
            logger.info(f"MCP-Server '{server['name']}': {len(mcp_tools)} Tools geladen")

        elif server_type == "rest":
            rest_tools = create_rest_tools(server)
            active_tools.extend(rest_tools)
            logger.info(f"REST-Server '{server['name']}': {len(rest_tools)} Tools geladen")

    return active_tools
