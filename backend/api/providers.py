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

from models import Provider, get_session
from core.plugin_loader import get_provider, list_available_providers

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
async def get_provider_types():
    """Gibt alle registrierten Provider-Typen zurück (aus PluginLoader)."""
    return list_available_providers()


@router.get("")
async def list_providers(db: AsyncSession = Depends(get_session)):
    result = await db.execute(select(Provider).order_by(Provider.created_at))
    providers = result.scalars().all()
    return [p.to_dict() for p in providers]


@router.post("", status_code=201)
async def create_provider(
    data: ProviderCreate, db: AsyncSession = Depends(get_session)
):
    provider = Provider(
        name=data.name,
        type=data.type,
        base_url=data.base_url,
        api_key=data.api_key,
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
    provider_id: str, db: AsyncSession = Depends(get_session)
):
    provider = await db.get(Provider, provider_id)
    if not provider:
        raise HTTPException(404, "Provider nicht gefunden")
    return provider.to_dict()


@router.put("/{provider_id}")
async def update_provider(
    provider_id: str,
    data: ProviderUpdate,
    db: AsyncSession = Depends(get_session),
):
    provider = await db.get(Provider, provider_id)
    if not provider:
        raise HTTPException(404, "Provider nicht gefunden")

    for field, value in data.model_dump(exclude_none=True).items():
        setattr(provider, field, value)

    await db.commit()
    await db.refresh(provider)
    return provider.to_dict()


@router.delete("/{provider_id}", status_code=204)
async def delete_provider(
    provider_id: str, db: AsyncSession = Depends(get_session)
):
    provider = await db.get(Provider, provider_id)
    if not provider:
        raise HTTPException(404, "Provider nicht gefunden")
    await db.delete(provider)
    await db.commit()


@router.get("/{provider_id}/models")
async def list_provider_models(
    provider_id: str, db: AsyncSession = Depends(get_session)
):
    """Ruft verfügbare Modelle vom Provider ab."""
    provider_record = await db.get(Provider, provider_id)
    if not provider_record:
        raise HTTPException(404, "Provider nicht gefunden")

    provider_instance = get_provider(
        provider_record.type,
        provider_record.to_dict(),
    )
    if not provider_instance:
        raise HTTPException(400, f"Unbekannter Provider-Typ: {provider_record.type}")

    models = await provider_instance.list_models()
    return {"models": models}


@router.post("/{provider_id}/test")
async def test_provider(
    provider_id: str, db: AsyncSession = Depends(get_session)
):
    """Testet die Verbindung zum Provider."""
    provider_record = await db.get(Provider, provider_id)
    if not provider_record:
        raise HTTPException(404, "Provider nicht gefunden")

    provider_instance = get_provider(
        provider_record.type,
        provider_record.to_dict(),
    )
    if not provider_instance:
        raise HTTPException(400, f"Unbekannter Provider-Typ: {provider_record.type}")

    ok = await provider_instance.test_connection()
    return {"success": ok, "message": "Verbunden" if ok else "Verbindung fehlgeschlagen"}
