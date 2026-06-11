"""
Settings-API – App-Einstellungen (Key-Value Store).

GET  /api/settings          – Alle Einstellungen
PUT  /api/settings          – Mehrere Einstellungen auf einmal setzen
GET  /api/settings/{key}    – Einzelne Einstellung
PUT  /api/settings/{key}    – Einzelne Einstellung setzen
"""

from typing import Any, Dict

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import Settings, get_session

router = APIRouter(prefix="/api/settings", tags=["settings"])

# Standardwerte
DEFAULT_SETTINGS = {
    "theme": "dark",
    "language": "de",
    "default_provider_id": "",
    "streaming_enabled": "true",
    "tool_calling_mode": "auto",  # auto | inject | disabled
}


@router.get("")
async def get_settings(db: AsyncSession = Depends(get_session)):
    """Gibt alle Einstellungen inkl. Standardwerte zurück."""
    result = await db.execute(select(Settings))
    stored = {s.key: s.value for s in result.scalars().all()}
    # Standardwerte mit gespeicherten Werten zusammenführen
    merged = {**DEFAULT_SETTINGS, **stored}
    return merged


@router.put("")
async def update_settings(
    data: Dict[str, Any], db: AsyncSession = Depends(get_session)
):
    """Setzt mehrere Einstellungen auf einmal."""
    for key, value in data.items():
        existing = await db.get(Settings, key)
        if existing:
            existing.value = str(value)
        else:
            db.add(Settings(key=key, value=str(value)))
    await db.commit()
    return {"success": True}


@router.put("/{key}")
async def set_setting(
    key: str, data: Dict[str, Any], db: AsyncSession = Depends(get_session)
):
    value = str(data.get("value", ""))
    existing = await db.get(Settings, key)
    if existing:
        existing.value = value
    else:
        db.add(Settings(key=key, value=value))
    await db.commit()
    return {"key": key, "value": value}
