"""
Provider-API – CRUD für KI-Provider-Konfigurationen.

Endpoints:
  GET    /api/providers           – Alle Provider
  POST   /api/providers           – Provider erstellen
  GET    /api/providers/{id}      – Einzelner Provider
  PUT    /api/providers/{id}      – Provider aktualisieren
  DELETE /api/providers/{id}      – Provider löschen
  GET    /api/providers/{id}/models – Verfügbare Modelle
  POST   /api/providers/{id}/test – Verbindung testen
  GET    /api/providers/types     – Registrierte Provider-Typen
"""

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import Provider, User, get_session
from core.plugin_loader import get_provider, list_available_providers
from core.auth import (
    can_use_provider, get_current_user, require_admin, user_provider_ids,
)
from core.crypto import decrypt_secret, encrypt_secret


async def _provider_config(db, record: Provider) -> dict:
    """Provider-Konfiguration mit entschlüsseltem API-Key (für interne Nutzung)."""
    cfg = record.to_dict()
    cfg["api_key"] = await decrypt_secret(db, record.api_key)
    return cfg

router = APIRouter(prefix="/api/providers", tags=["providers"])


class ProviderCreate(BaseModel):
    name: str
    type: str
    base_url: Optional[str] = None
    api_key: Optional[str] = None
    default_model: Optional[str] = None
    custom_headers: Optional[Dict[str, str]] = None
    is_enabled: bool = True


class ProviderUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    base_url: Optional[str] = None
    api_key: Optional[str] = None
    default_model: Optional[str] = None
    custom_headers: Optional[Dict[str, str]] = None
    is_enabled: Optional[bool] = None


@router.get("/types")
async def get_provider_types(_: User = Depends(require_admin)):
    """Gibt alle registrierten Provider-Typen zurück (aus PluginLoader)."""
    return list_available_providers()


@router.get("")
async def list_providers(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Admin sieht alle Provider, normale Nutzer nur die ihnen zugewiesenen."""
    result = await db.execute(select(Provider).order_by(Provider.created_at))
    providers = result.scalars().all()
    if user.role != "admin":
        allowed = await user_provider_ids(db, user.id)
        providers = [p for p in providers if p.id in allowed]
    return [p.to_dict() for p in providers]


@router.post("", status_code=201)
async def create_provider(
    data: ProviderCreate,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    provider = Provider(
        name=data.name,
        type=data.type,
        base_url=data.base_url,
        api_key=await encrypt_secret(db, data.api_key),
        default_model=data.default_model,
        custom_headers=data.custom_headers or {},
        is_enabled=data.is_enabled,
    )
    db.add(provider)
    await db.commit()
    await db.refresh(provider)
    return provider.to_dict()


@router.get("/{provider_id}")
async def get_provider_by_id(
    provider_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    provider = await db.get(Provider, provider_id)
    if not provider:
        raise HTTPException(404, "Provider nicht gefunden")
    if not await can_use_provider(db, user, provider_id):
        raise HTTPException(403, "Kein Zugriff auf diesen Provider.")
    return provider.to_dict()


@router.put("/{provider_id}")
async def update_provider(
    provider_id: str,
    data: ProviderUpdate,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    provider = await db.get(Provider, provider_id)
    if not provider:
        raise HTTPException(404, "Provider nicht gefunden")

    fields = data.model_dump(exclude_none=True)
    if "api_key" in fields:
        fields["api_key"] = await encrypt_secret(db, fields["api_key"])
    for field, value in fields.items():
        setattr(provider, field, value)

    await db.commit()
    await db.refresh(provider)
    return provider.to_dict()


@router.delete("/{provider_id}", status_code=204)
async def delete_provider(
    provider_id: str,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    provider = await db.get(Provider, provider_id)
    if not provider:
        raise HTTPException(404, "Provider nicht gefunden")
    await db.delete(provider)
    await db.commit()


@router.get("/{provider_id}/models")
async def list_provider_models(
    provider_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Ruft verfügbare Modelle vom Provider ab."""
    provider_record = await db.get(Provider, provider_id)
    if not provider_record:
        raise HTTPException(404, "Provider nicht gefunden")
    if not await can_use_provider(db, user, provider_id):
        raise HTTPException(403, "Kein Zugriff auf diesen Provider.")

    provider_instance = get_provider(
        provider_record.type,
        await _provider_config(db, provider_record),
    )
    if not provider_instance:
        raise HTTPException(400, f"Unbekannter Provider-Typ: {provider_record.type}")

    models = await provider_instance.list_models()
    return {"models": models}


@router.post("/{provider_id}/test")
async def test_provider(
    provider_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Testet die Verbindung zum Provider."""
    provider_record = await db.get(Provider, provider_id)
    if not provider_record:
        raise HTTPException(404, "Provider nicht gefunden")
    if not await can_use_provider(db, user, provider_id):
        raise HTTPException(403, "Kein Zugriff auf diesen Provider.")

    provider_instance = get_provider(
        provider_record.type,
        await _provider_config(db, provider_record),
    )
    if not provider_instance:
        raise HTTPException(400, f"Unbekannter Provider-Typ: {provider_record.type}")

    ok = await provider_instance.test_connection()
    return {"success": ok, "message": "Verbunden" if ok else "Verbindung fehlgeschlagen"}
