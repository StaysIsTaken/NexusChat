"""
Admin-API – Betriebsfunktionen (nur Administrator).

Endpoints:
  GET /api/admin/backup   – SQLite-Datenbank als Download
"""

import asyncio
import os

import httpx
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import DB_PATH, Provider, ToolServer, User, get_session
from core.auth import require_admin
from core.crypto import decrypt_secret
from core.mcp_client import MCPClient
from core.plugin_loader import get_provider

router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.get("/backup")
async def download_backup(_: User = Depends(require_admin)):
    """Lädt die komplette SQLite-Datenbank herunter (Sicherung)."""
    if not os.path.exists(DB_PATH):
        raise HTTPException(404, "Keine Datenbank gefunden.")
    return FileResponse(
        DB_PATH,
        media_type="application/octet-stream",
        filename="nexuschat-backup.db",
    )


@router.get("/health")
async def system_health(
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """Prüft die Erreichbarkeit aller Provider und Tool-Server (parallel)."""
    providers = (await db.execute(select(Provider))).scalars().all()
    tool_servers = (await db.execute(select(ToolServer))).scalars().all()

    # Keys vorab sequenziell entschlüsseln – danach kein DB-Zugriff in den parallelen Checks
    prov_cfgs = []
    for p in providers:
        cfg = p.to_dict()
        cfg["api_key"] = await decrypt_secret(db, p.api_key)
        prov_cfgs.append((p, cfg))
    tool_keys = [(s, await decrypt_secret(db, s.api_key)) for s in tool_servers]

    async def check_provider(p: Provider, cfg: dict) -> dict:
        online, message = False, "Unbekannter Typ"
        try:
            inst = get_provider(p.type, cfg)
            if inst:
                online = await inst.test_connection()
                message = "Erreichbar" if online else "Nicht erreichbar"
        except Exception as e:
            message = str(e)[:120]
        return {
            "kind": "provider", "id": p.id, "name": p.name, "type": p.type,
            "enabled": bool(p.is_enabled), "online": online, "message": message,
        }

    async def check_tool(s: ToolServer, key) -> dict:
        online, message = False, "Unbekannter Typ"
        try:
            if s.type == "mcp":
                client = MCPClient(server_url=s.url or "", api_key=key)
                online = await client.test_connection()
                message = "Erreichbar" if online else "Nicht erreichbar"
            elif s.type == "rest":
                async with httpx.AsyncClient(timeout=5) as hc:
                    r = await hc.get(s.url or "")
                    online = r.status_code < 500
                    message = f"HTTP {r.status_code}"
        except Exception as e:
            message = str(e)[:120]
        return {
            "kind": "tool", "id": s.id, "name": s.name, "type": s.type,
            "enabled": bool(s.is_enabled), "online": online, "message": message,
        }

    results = await asyncio.gather(
        *[check_provider(p, cfg) for p, cfg in prov_cfgs],
        *[check_tool(s, k) for s, k in tool_keys],
    )
    return list(results)
