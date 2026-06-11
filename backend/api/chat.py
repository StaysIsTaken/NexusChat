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

import json
import logging
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import Chat, Message, Provider, ToolServer, get_session, async_session_maker
from core.plugin_loader import get_provider
from core.tool_caller import ToolCaller, load_active_tools

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
async def list_chats(db: AsyncSession = Depends(get_session)):
    result = await db.execute(
        select(Chat).order_by(Chat.updated_at.desc())
    )
    chats = result.scalars().all()
    return [c.to_dict() for c in chats]


@router.post("/api/chats", status_code=201)
async def create_chat(data: ChatCreate, db: AsyncSession = Depends(get_session)):
    chat = Chat(
        title=data.title or "Neues Gespräch",
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
async def get_chat(chat_id: str, db: AsyncSession = Depends(get_session)):
    """Gibt Chat inkl. vollständigem Nachrichtenverlauf zurück."""
    result = await db.execute(
        select(Chat).where(Chat.id == chat_id)
    )
    chat = result.scalar_one_or_none()
    if not chat:
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
    chat_id: str, data: ChatUpdate, db: AsyncSession = Depends(get_session)
):
    chat = await db.get(Chat, chat_id)
    if not chat:
        raise HTTPException(404, "Chat nicht gefunden")

    for field, value in data.model_dump(exclude_none=True).items():
        setattr(chat, field, value)
    chat.updated_at = datetime.utcnow()

    await db.commit()
    await db.refresh(chat)
    return chat.to_dict()


@router.delete("/api/chats/{chat_id}", status_code=204)
async def delete_chat(chat_id: str, db: AsyncSession = Depends(get_session)):
    chat = await db.get(Chat, chat_id)
    if not chat:
        raise HTTPException(404, "Chat nicht gefunden")
    await db.delete(chat)
    await db.commit()


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
    logger.info(f"WebSocket verbunden: chat_id={chat_id}")

    try:
        while True:
            # Warte auf Nachricht vom Client
            raw = await websocket.receive_text()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Ungültiges JSON"})
                continue

            user_content = data.get("content", "").strip()
            if not user_content:
                continue

            # Eigene Session für diesen Request (nicht WebSocket-lebendig)
            async with async_session_maker() as db:
                await _handle_chat_message(websocket, db, chat_id, user_content)

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
):
    """Verarbeitet eine eingehende Nachricht und streamt die Antwort."""

    # Chat laden
    chat = await db.get(Chat, chat_id)
    if not chat:
        await websocket.send_json({"type": "error", "message": "Chat nicht gefunden"})
        return

    # Nutzernachricht in DB speichern
    user_msg = Message(
        chat_id=chat_id,
        role="user",
        content=user_content,
    )
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

    provider_instance = get_provider(provider_record.type, provider_record.to_dict())
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
        all_servers = [s.to_dict() for s in all_servers_result.scalars().all()]
        active_tools = await load_active_tools(tool_server_ids, all_servers)

    # Tool-Caller initialisieren und Antwort streamen
    tool_caller = ToolCaller(tools=active_tools)
    full_response = ""
    all_tool_calls = []

    async for event in tool_caller.run(
        conversation=conversation,
        provider=provider_instance,
        model=model,
        system_prompt=chat.system_prompt,
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
            if chat.title == "Neues Gespräch" and len(history_msgs) == 1:
                chat.title = user_content[:50] + ("..." if len(user_content) > 50 else "")
            chat.updated_at = datetime.utcnow()
            await db.commit()

        await websocket.send_json(event)
