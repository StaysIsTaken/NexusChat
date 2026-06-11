"""
Chat-API – Gesprächsverwaltung und WebSocket-Streaming.

REST Endpoints:
  GET    /api/chats               – Alle Chats
  POST   /api/chats               – Neuen Chat erstellen
  GET    /api/chats/{id}          – Chat mit Nachrichten
  PUT    /api/chats/{id}          – Chat aktualisieren (Titel, Provider, etc.)
  DELETE /api/chats/{id}          – Chat löschen

WebSocket:
  WS /ws/chat/{id}                – Streaming-Kanal für einen Chat

  Client sendet:  {"content": "Nutzernachricht"}
  Server sendet:  {"type": "token", "content": "..."}
                  {"type": "tool_start", "name": "...", "arguments": {...}}
                  {"type": "tool_end",   "name": "...", "result": "..."}
                  {"type": "done",       "tool_calls": [...]}
                  {"type": "error",      "message": "..."}
"""

import asyncio
import json
import logging
import re
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from models import Chat, Message, Provider, ToolServer, User, get_session, async_session_maker
from core.plugin_loader import get_provider
from core.tool_caller import ToolCaller, load_active_tools
from providers.base import ChatMessage
from core.auth import (
    authenticate_token, get_current_user, user_provider_ids, user_tool_ids,
)
from core.crypto import decrypt_secret

logger = logging.getLogger(__name__)

router = APIRouter(tags=["chat"])


# ── REST Endpoints ──────────────────────────────────────────────────────────

class ChatCreate(BaseModel):
    title: Optional[str] = "Neues Gespräch"
    provider_id: Optional[str] = None
    model_name: Optional[str] = None
    active_tool_ids: Optional[List[str]] = None
    system_prompt: Optional[str] = None


class ChatUpdate(BaseModel):
    title: Optional[str] = None
    provider_id: Optional[str] = None
    model_name: Optional[str] = None
    active_tool_ids: Optional[List[str]] = None
    system_prompt: Optional[str] = None


@router.get("/api/chats")
async def list_chats(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    result = await db.execute(
        select(Chat).where(Chat.user_id == user.id).order_by(Chat.updated_at.desc())
    )
    chats = result.scalars().all()
    return [c.to_dict() for c in chats]


@router.post("/api/chats", status_code=201)
async def create_chat(
    data: ChatCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    chat = Chat(
        title=data.title or "Neues Gespräch",
        user_id=user.id,
        provider_id=data.provider_id,
        model_name=data.model_name,
        active_tool_ids=data.active_tool_ids or [],
        system_prompt=data.system_prompt,
    )
    db.add(chat)
    await db.commit()
    await db.refresh(chat)
    return chat.to_dict()


@router.get("/api/chats/{chat_id}")
async def get_chat(
    chat_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Gibt Chat inkl. vollständigem Nachrichtenverlauf zurück."""
    result = await db.execute(
        select(Chat).where(Chat.id == chat_id)
    )
    chat = result.scalar_one_or_none()
    if not chat or chat.user_id != user.id:
        raise HTTPException(404, "Chat nicht gefunden")

    # Nachrichten separat laden – NIEMALS chat.messages = ... benutzen.
    # SQLAlchemy async erlaubt kein lazy loading über ORM-Relationships;
    # der Setter würde intern einen synchronen DB-Aufruf triggern (MissingGreenlet).
    msg_result = await db.execute(
        select(Message).where(Message.chat_id == chat_id).order_by(Message.timestamp)
    )
    messages = msg_result.scalars().all()

    chat_dict = chat.to_dict()
    chat_dict["messages"] = [m.to_dict() for m in messages]
    return chat_dict


@router.put("/api/chats/{chat_id}")
async def update_chat(
    chat_id: str,
    data: ChatUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    chat = await db.get(Chat, chat_id)
    if not chat or chat.user_id != user.id:
        raise HTTPException(404, "Chat nicht gefunden")

    fields = data.model_dump(exclude_none=True)

    # Nicht-Admins dürfen nur zugewiesene Provider/Tools setzen
    if user.role != "admin":
        if fields.get("provider_id"):
            allowed_providers = await user_provider_ids(db, user.id)
            if fields["provider_id"] not in allowed_providers:
                raise HTTPException(403, "Kein Zugriff auf diesen Provider.")
        if "active_tool_ids" in fields:
            allowed = await user_tool_ids(db, user.id)
            fields["active_tool_ids"] = [t for t in fields["active_tool_ids"] if t in allowed]

    for field, value in fields.items():
        setattr(chat, field, value)
    chat.updated_at = datetime.utcnow()

    await db.commit()
    await db.refresh(chat)
    return chat.to_dict()


@router.delete("/api/chats/{chat_id}", status_code=204)
async def delete_chat(
    chat_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    chat = await db.get(Chat, chat_id)
    if not chat or chat.user_id != user.id:
        raise HTTPException(404, "Chat nicht gefunden")
    await db.delete(chat)
    await db.commit()


class EditMessage(BaseModel):
    message_id: str
    content: str


@router.post("/api/chats/{chat_id}/edit_message")
async def edit_message(
    chat_id: str,
    data: EditMessage,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """
    Bearbeitet eine (Nutzer-)Nachricht und entfernt alle nachfolgenden Nachrichten.
    Danach kann der Client per WebSocket-'regenerate' eine neue Antwort anfordern.
    """
    chat = await db.get(Chat, chat_id)
    if not chat or chat.user_id != user.id:
        raise HTTPException(404, "Chat nicht gefunden")

    msg = await db.get(Message, data.message_id)
    if not msg or msg.chat_id != chat_id:
        raise HTTPException(404, "Nachricht nicht gefunden")

    # Alles nach dieser Nachricht löschen, dann Inhalt aktualisieren
    await db.execute(
        delete(Message).where(
            Message.chat_id == chat_id, Message.timestamp > msg.timestamp
        )
    )
    msg.content = data.content
    chat.updated_at = datetime.utcnow()
    await db.commit()
    return {"ok": True}


@router.get("/api/search")
async def search_messages(
    q: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Volltextsuche über alle Nachrichten der eigenen Chats."""
    query = q.strip()
    if not query:
        return []
    # Chats des Nutzers
    chat_rows = await db.execute(select(Chat).where(Chat.user_id == user.id))
    chats = {c.id: c for c in chat_rows.scalars().all()}
    if not chats:
        return []
    msg_rows = await db.execute(
        select(Message)
        .where(Message.chat_id.in_(list(chats.keys())))
        .where(Message.content.ilike(f"%{query}%"))
        .order_by(Message.timestamp.desc())
    )
    seen: dict = {}
    for m in msg_rows.scalars().all():
        if m.chat_id in seen:
            continue
        chat = chats[m.chat_id]
        snippet = m.content.strip().replace("\n", " ")
        if len(snippet) > 120:
            snippet = snippet[:120] + "…"
        seen[m.chat_id] = {
            "id": chat.id,
            "title": chat.title,
            "updated_at": chat.updated_at.isoformat() if chat.updated_at else None,
            "snippet": snippet,
        }
    return list(seen.values())


# ── WebSocket ───────────────────────────────────────────────────────────────

@router.websocket("/ws/chat/{chat_id}")
async def chat_websocket(websocket: WebSocket, chat_id: str):
    """
    WebSocket-Endpunkt für Chat-Streaming.

    Der Client verbindet sich und sendet Nachrichten als JSON:
    {"content": "Deine Nachricht hier"}

    Der Server streamt die Antwort Token für Token zurück
    und gibt Tool-Calls als strukturierte Events aus.
    """
    await websocket.accept()

    # Authentifizierung via Query-Parameter ?token=... (WS kann keine Header setzen)
    token = websocket.query_params.get("token", "")
    async with async_session_maker() as db:
        auth_user = await authenticate_token(token, db) if token else None

    if auth_user is None:
        await websocket.send_json({"type": "error", "message": "Nicht angemeldet"})
        await websocket.close(code=4401)
        return

    user_id = auth_user.id
    user_role = auth_user.role
    logger.info(f"WebSocket verbunden: chat_id={chat_id}, user={auth_user.username}")

    try:
        while True:
            # Warte auf eine Chat-Nachricht vom Client
            raw = await websocket.receive_text()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Ungültiges JSON"})
                continue

            user_content = (data.get("content") or "").strip()
            is_regenerate = data.get("type") == "regenerate"
            if not user_content and not is_regenerate:
                continue  # Steuernachrichten außerhalb einer Generierung ignorieren

            # Pro Turn: Abbruch-Signal, Entscheidungs-Queue (Tool-Bestätigung), Disconnect-Flag
            stop_event = asyncio.Event()
            decision_queue: asyncio.Queue = asyncio.Queue()
            client_gone = asyncio.Event()

            async def confirm(name: str, args: dict) -> bool:
                """Fragt den Client ob ein Tool ausgeführt werden darf."""
                try:
                    await websocket.send_json(
                        {"type": "tool_confirm", "name": name, "arguments": args}
                    )
                except Exception:
                    return False
                getter = asyncio.create_task(decision_queue.get())
                gone = asyncio.create_task(client_gone.wait())
                done, _ = await asyncio.wait(
                    {getter, gone}, return_when=asyncio.FIRST_COMPLETED
                )
                if getter in done:
                    gone.cancel()
                    return bool(getter.result())
                getter.cancel()
                return False  # Client weg → Ausführung ablehnen

            async def generate():
                async with async_session_maker() as db:
                    await _handle_chat_message(
                        websocket, db, chat_id, user_content, user_id, user_role,
                        stop_event, confirm, is_regenerate,
                    )

            gen_task = asyncio.create_task(generate())

            # Während generiert wird gleichzeitig auf 'stop' und 'tool_decision' hören.
            # WICHTIG: immer nur EIN receive_text()-Task gleichzeitig – und einen
            # abgebrochenen Reader vor dem nächsten receive_text() abwarten, sonst
            # wirft websockets "cannot call recv while another coroutine is waiting".
            reader = asyncio.create_task(websocket.receive_text())
            try:
                while not gen_task.done():
                    done, _ = await asyncio.wait(
                        {gen_task, reader}, return_when=asyncio.FIRST_COMPLETED
                    )
                    if reader in done:
                        try:
                            ctrl = json.loads(reader.result())
                        except WebSocketDisconnect:
                            client_gone.set()
                            stop_event.set()
                            await gen_task  # sauber beenden (speichert Teilantwort)
                            raise
                        except Exception:
                            ctrl = None
                        if isinstance(ctrl, dict):
                            ct = ctrl.get("type")
                            if ct == "stop":
                                stop_event.set()
                            elif ct == "tool_decision":
                                decision_queue.put_nowait(bool(ctrl.get("approved")))
                        # Neuen Reader nur starten wenn noch generiert wird
                        if not gen_task.done():
                            reader = asyncio.create_task(websocket.receive_text())
            finally:
                # Ausstehenden Reader abbrechen UND abwarten (Waiter sauber entfernen)
                if not reader.done():
                    reader.cancel()
                    try:
                        await reader
                    except BaseException:
                        pass

            await gen_task  # eventuelle Exceptions propagieren

    except WebSocketDisconnect:
        logger.info(f"WebSocket getrennt: chat_id={chat_id}")
    except Exception as e:
        logger.error(f"WebSocket-Fehler: {e}", exc_info=True)
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass


async def _handle_chat_message(
    websocket: WebSocket,
    db: AsyncSession,
    chat_id: str,
    user_content: str,
    user_id: str,
    user_role: str,
    stop_event: Optional[asyncio.Event] = None,
    confirm=None,
    regenerate: bool = False,
):
    """Verarbeitet eine eingehende Nachricht und streamt die Antwort."""

    # Chat laden + Besitz prüfen
    chat = await db.get(Chat, chat_id)
    if not chat or chat.user_id != user_id:
        await websocket.send_json({"type": "error", "message": "Chat nicht gefunden"})
        return

    if regenerate:
        # Neu generieren: am Ende stehende Assistenten-Nachrichten entfernen,
        # damit der Verlauf wieder mit der letzten Nutzernachricht endet.
        existing = (await db.execute(
            select(Message).where(Message.chat_id == chat_id).order_by(Message.timestamp)
        )).scalars().all()
        for m in reversed(existing):
            if m.role == "assistant":
                await db.delete(m)
            else:
                break
        await db.commit()
    else:
        # Nutzernachricht in DB speichern
        user_msg = Message(chat_id=chat_id, role="user", content=user_content)
        db.add(user_msg)
        await db.commit()

    # Bisherigen Gesprächsverlauf laden (ohne System-Nachrichten – die kommen via system_prompt)
    msg_result = await db.execute(
        select(Message)
        .where(Message.chat_id == chat_id)
        .where(Message.role.in_(["user", "assistant"]))
        .order_by(Message.timestamp)
    )
    history_msgs = msg_result.scalars().all()

    conversation = [
        {"role": m.role, "content": m.content}
        for m in history_msgs
    ]

    # Provider laden
    if not chat.provider_id:
        await websocket.send_json({"type": "error", "message": "Kein Provider konfiguriert"})
        return

    provider_record = await db.get(Provider, chat.provider_id)
    if not provider_record or not provider_record.is_enabled:
        await websocket.send_json({"type": "error", "message": "Provider nicht verfügbar"})
        return

    # Zugriffskontrolle: Nicht-Admins dürfen nur zugewiesene Provider nutzen
    if user_role != "admin":
        allowed_providers = await user_provider_ids(db, user_id)
        if chat.provider_id not in allowed_providers:
            await websocket.send_json(
                {"type": "error", "message": "Kein Zugriff auf diesen Provider."}
            )
            return

    provider_config = provider_record.to_dict()
    provider_config["api_key"] = await decrypt_secret(db, provider_record.api_key)
    provider_instance = get_provider(provider_record.type, provider_config)
    if not provider_instance:
        await websocket.send_json({"type": "error", "message": "Provider-Typ unbekannt"})
        return

    model = chat.model_name or provider_record.default_model or ""
    if not model:
        await websocket.send_json({"type": "error", "message": "Kein Modell ausgewählt"})
        return

    # Aktive Tools laden
    tool_server_ids = chat.active_tool_ids or []
    active_tools = []
    if tool_server_ids:
        all_servers_result = await db.execute(select(ToolServer))
        all_servers = []
        for s in all_servers_result.scalars().all():
            sd = s.to_dict()
            sd["api_key"] = await decrypt_secret(db, s.api_key)  # für Tool-Aufrufe nötig
            all_servers.append(sd)
        active_tools = await load_active_tools(tool_server_ids, all_servers)

    # Tool-Caller initialisieren und Antwort streamen
    tool_caller = ToolCaller(tools=active_tools)
    full_response = ""
    all_tool_calls = []
    # Erster Austausch? → danach automatisch einen Titel erzeugen
    first_exchange = chat.title == "Neues Gespräch" and len(history_msgs) <= 1
    first_user_content = history_msgs[0].content if history_msgs else user_content

    # Wenn der Client mitten im Stream wegnavigiert, bricht send_json ab.
    # Wir wollen die Generierung trotzdem zu Ende führen und die Antwort
    # speichern – damit sie beim Zurückkehren in den Chat geladen wird.
    client_connected = True

    async def safe_send(payload: dict) -> None:
        nonlocal client_connected
        if not client_connected:
            return
        try:
            await websocket.send_json(payload)
        except Exception:
            client_connected = False
            logger.info(
                f"Client getrennt – Generierung läuft weiter und wird "
                f"gespeichert (chat_id={chat_id})"
            )

    async for event in tool_caller.run(
        conversation=conversation,
        provider=provider_instance,
        model=model,
        system_prompt=chat.system_prompt,
        stop_event=stop_event,
        confirm=confirm,
    ):
        if event["type"] == "token":
            full_response += event["content"]
        elif event["type"] == "done":
            all_tool_calls = event.get("tool_calls", [])
            # Assistent-Antwort VOR dem Senden von "done" in DB speichern,
            # damit _loadChat() im Frontend die fertige Antwort vorfindet.
            assistant_msg = Message(
                chat_id=chat_id,
                role="assistant",
                content=full_response,
                tool_calls=[
                    {"name": tc["name"], "arguments": tc["arguments"]}
                    for tc in all_tool_calls
                ],
                tool_results=[
                    {"name": tc["name"], "result": tc["result"]}
                    for tc in all_tool_calls
                ],
            )
            db.add(assistant_msg)
            # Sofort-Fallback-Titel (wird ggf. gleich durch LLM-Titel ersetzt)
            if first_exchange:
                chat.title = first_user_content[:50] + ("…" if len(first_user_content) > 50 else "")
            chat.updated_at = datetime.utcnow()
            await db.commit()

        await safe_send(event)

    # Auto-Titel per LLM (best effort, nach dem Stream)
    if first_exchange and full_response.strip():
        title = await _generate_title(
            provider_instance, model, first_user_content, full_response
        )
        if title:
            chat.title = title
            await db.commit()
            await safe_send({"type": "title", "title": title})


async def _generate_title(provider, model, user_msg: str, assistant_msg: str) -> str:
    """Erzeugt einen kurzen Gesprächstitel. Bei Fehlern leerer String."""
    prompt = (
        "Erzeuge einen sehr kurzen, prägnanten Titel (höchstens 5 Wörter, "
        "keine Anführungszeichen, kein Satzzeichen am Ende) für dieses Gespräch:\n\n"
        f"Nutzer: {user_msg[:400]}\n"
        f"Assistent: {assistant_msg[:400]}"
    )
    out = ""
    try:
        async for tok in provider.chat([ChatMessage(role="user", content=prompt)], model=model):
            out += tok
            if len(out) > 240:
                break
    except Exception as e:
        logger.info(f"Auto-Titel fehlgeschlagen: {e}")
        return ""
    # Think-Blöcke und Anführungszeichen entfernen, erste Zeile nehmen
    out = re.sub(r"<think>.*?</think>", "", out, flags=re.DOTALL | re.IGNORECASE)
    out = out.strip().strip('"').strip("'").strip()
    if not out:
        return ""
    return out.split("\n")[0].strip()[:60]
