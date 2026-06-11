"""
Tools-API – CRUD für Tool-Server-Konfigurationen.

Endpoints:
  GET    /api/tools               – Alle Tool-Server
  POST   /api/tools               – Tool-Server erstellen
  GET    /api/tools/{id}          – Einzelner Tool-Server
  PUT    /api/tools/{id}          – Tool-Server aktualisieren
  DELETE /api/tools/{id}          – Tool-Server löschen
  GET    /api/tools/{id}/tools    – Verfügbare Tools des Servers
  POST   /api/tools/{id}/test     – Verbindung testen
"""

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import ToolServer, User, get_session
from core.mcp_client import MCPClient
from core.auth import (
    can_use_tool, get_current_user, require_admin, user_tool_ids,
)
from tools.rest_tool import create_rest_tools

router = APIRouter(prefix="/api/tools", tags=["tools"])


class ToolServerCreate(BaseModel):
    name: str
    type: str   # mcp | rest | custom
    url: Optional[str] = None
    api_key: Optional[str] = None
    config: Optional[Dict[str, Any]] = None
    is_enabled: bool = True


class ToolServerUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    url: Optional[str] = None
    api_key: Optional[str] = None
    config: Optional[Dict[str, Any]] = None
    is_enabled: Optional[bool] = None


@router.get("")
async def list_tool_servers(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Admin sieht alle Tool-Server, normale Nutzer nur die zugewiesenen."""
    result = await db.execute(select(ToolServer).order_by(ToolServer.created_at))
    servers = result.scalars().all()
    if user.role != "admin":
        allowed = await user_tool_ids(db, user.id)
        servers = [s for s in servers if s.id in allowed]
    return [s.to_dict() for s in servers]


@router.post("", status_code=201)
async def create_tool_server(
    data: ToolServerCreate,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    server = ToolServer(
        name=data.name,
        type=data.type,
        url=data.url,
        api_key=data.api_key,
        config=data.config or {},
        is_enabled=data.is_enabled,
    )
    db.add(server)
    await db.commit()
    await db.refresh(server)
    return server.to_dict()


@router.get("/{server_id}")
async def get_tool_server(
    server_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    server = await db.get(ToolServer, server_id)
    if not server:
        raise HTTPException(404, "Tool-Server nicht gefunden")
    if not await can_use_tool(db, user, server_id):
        raise HTTPException(403, "Kein Zugriff auf diesen Tool-Server.")
    return server.to_dict()


@router.put("/{server_id}")
async def update_tool_server(
    server_id: str,
    data: ToolServerUpdate,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    server = await db.get(ToolServer, server_id)
    if not server:
        raise HTTPException(404, "Tool-Server nicht gefunden")

    for field, value in data.model_dump(exclude_none=True).items():
        setattr(server, field, value)

    await db.commit()
    await db.refresh(server)
    return server.to_dict()


@router.delete("/{server_id}", status_code=204)
async def delete_tool_server(
    server_id: str,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    server = await db.get(ToolServer, server_id)
    if not server:
        raise HTTPException(404, "Tool-Server nicht gefunden")
    await db.delete(server)
    await db.commit()


@router.get("/{server_id}/tools")
async def list_server_tools(
    server_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Listet alle verfügbaren Tools des Servers auf."""
    server = await db.get(ToolServer, server_id)
    if not server:
        raise HTTPException(404, "Tool-Server nicht gefunden")
    if not await can_use_tool(db, user, server_id):
        raise HTTPException(403, "Kein Zugriff auf diesen Tool-Server.")

    server_dict = server.to_dict()
    tools_info = []

    if server.type == "mcp":
        client = MCPClient(
            server_url=server.url or "",
            api_key=server.api_key,
        )
        tools = await client.list_tools()
        tools_info = [
            {
                "name": t.name,
                "description": t.description,
                "parameters": {
                    pname: {"type": p.type, "description": p.description, "required": p.required}
                    for pname, p in t.parameters.items()
                },
            }
            for t in tools
        ]

    elif server.type == "rest":
        tools = create_rest_tools(server_dict)
        tools_info = [
            {
                "name": t.name,
                "description": t.description,
                "parameters": {
                    pname: {"type": p.type, "description": p.description, "required": p.required}
                    for pname, p in t.parameters.items()
                },
            }
            for t in tools
        ]

    return {"tools": tools_info, "count": len(tools_info)}


@router.post("/{server_id}/test")
async def test_tool_server(
    server_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Testet die Verbindung zum Tool-Server."""
    server = await db.get(ToolServer, server_id)
    if not server:
        raise HTTPException(404, "Tool-Server nicht gefunden")
    if not await can_use_tool(db, user, server_id):
        raise HTTPException(403, "Kein Zugriff auf diesen Tool-Server.")

    if server.type == "mcp":
        client = MCPClient(
            server_url=server.url or "",
            api_key=server.api_key,
        )
        ok = await client.test_connection()
        message = "MCP-Server verbunden" if ok else "Verbindung zum MCP-Server fehlgeschlagen"

    elif server.type == "rest":
        # REST APIs haben keinen standardisierten Test-Endpunkt
        # Versuche die Base-URL zu erreichen
        import httpx
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(server.url or "")
                ok = resp.status_code < 500
                message = f"HTTP {resp.status_code}"
        except Exception as e:
            ok = False
            message = str(e)
    else:
        ok = False
        message = f"Unbekannter Server-Typ: {server.type}"

    return {"success": ok, "message": message}
