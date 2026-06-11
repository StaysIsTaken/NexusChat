"""
User-API – Benutzerverwaltung durch den Admin.

Alle Endpunkte erfordern Admin-Rechte.

Endpoints:
  GET    /api/users                  – Alle Benutzer inkl. zugewiesener Provider/Tools
  POST   /api/users                  – Neuen Benutzer anlegen
  DELETE /api/users/{id}             – Benutzer löschen (inkl. seiner Chats)
  PUT    /api/users/{id}/password    – Passwort zurücksetzen
  PUT    /api/users/{id}/providers   – Zugewiesene Provider setzen
  PUT    /api/users/{id}/tools       – Zugewiesene Tools setzen
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import delete, insert, select
from sqlalchemy.ext.asyncio import AsyncSession

from models import (
    Chat, Provider, ToolServer, User,
    get_session, user_providers, user_tools,
)
from core.auth import hash_password, require_admin

router = APIRouter(prefix="/api/users", tags=["users"])


class UserCreate(BaseModel):
    username: str
    password: str


class PasswordReset(BaseModel):
    password: str


class IdList(BaseModel):
    ids: List[str]


async def _assigned_provider_ids(db: AsyncSession, user_id: str) -> List[str]:
    rows = await db.execute(
        select(user_providers.c.provider_id).where(user_providers.c.user_id == user_id)
    )
    return [r[0] for r in rows.all()]


async def _assigned_tool_ids(db: AsyncSession, user_id: str) -> List[str]:
    rows = await db.execute(
        select(user_tools.c.tool_server_id).where(user_tools.c.user_id == user_id)
    )
    return [r[0] for r in rows.all()]


def _user_payload(user: User, provider_ids: List[str], tool_ids: List[str]) -> dict:
    d = user.to_dict()
    d["provider_ids"] = provider_ids
    d["tool_ids"] = tool_ids
    return d


@router.get("")
async def list_users(
    _: User = Depends(require_admin), db: AsyncSession = Depends(get_session)
):
    result = await db.execute(select(User).order_by(User.created_at))
    users = result.scalars().all()
    out = []
    for u in users:
        out.append(_user_payload(
            u,
            await _assigned_provider_ids(db, u.id),
            await _assigned_tool_ids(db, u.id),
        ))
    return out


@router.post("", status_code=201)
async def create_user(
    data: UserCreate,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    username = data.username.strip()
    if not username or not data.password:
        raise HTTPException(400, "Benutzername und Passwort erforderlich.")

    existing = await db.execute(select(User).where(User.username == username))
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(409, "Benutzername bereits vergeben.")

    user = User(
        username=username,
        password_hash=hash_password(data.password),
        role="user",
        must_change_password=True,  # beim ersten Login Passwort ändern
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return _user_payload(user, [], [])


@router.delete("/{user_id}", status_code=204)
async def delete_user(
    user_id: str,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(404, "Benutzer nicht gefunden")
    if user.role == "admin":
        raise HTTPException(403, "Der Administrator kann nicht gelöscht werden.")

    # Zuweisungen, Chats und den Benutzer selbst entfernen
    await db.execute(delete(user_providers).where(user_providers.c.user_id == user_id))
    await db.execute(delete(user_tools).where(user_tools.c.user_id == user_id))
    await db.execute(delete(Chat).where(Chat.user_id == user_id))
    await db.delete(user)
    await db.commit()


@router.put("/{user_id}/password")
async def reset_password(
    user_id: str,
    data: PasswordReset,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(404, "Benutzer nicht gefunden")
    if not data.password:
        raise HTTPException(400, "Passwort erforderlich.")
    user.password_hash = hash_password(data.password)
    user.must_change_password = True  # User muss es beim nächsten Login ändern
    await db.commit()
    return {"success": True}


@router.put("/{user_id}/providers")
async def set_user_providers(
    user_id: str,
    data: IdList,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(404, "Benutzer nicht gefunden")

    # Nur existierende Provider zulassen
    valid_rows = await db.execute(select(Provider.id).where(Provider.id.in_(data.ids)))
    valid_ids = {r[0] for r in valid_rows.all()}

    await db.execute(delete(user_providers).where(user_providers.c.user_id == user_id))
    for pid in valid_ids:
        await db.execute(insert(user_providers).values(user_id=user_id, provider_id=pid))
    await db.commit()
    return {"provider_ids": sorted(valid_ids)}


@router.put("/{user_id}/tools")
async def set_user_tools(
    user_id: str,
    data: IdList,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(404, "Benutzer nicht gefunden")

    valid_rows = await db.execute(select(ToolServer.id).where(ToolServer.id.in_(data.ids)))
    valid_ids = {r[0] for r in valid_rows.all()}

    await db.execute(delete(user_tools).where(user_tools.c.user_id == user_id))
    for tid in valid_ids:
        await db.execute(insert(user_tools).values(user_id=user_id, tool_server_id=tid))
    await db.commit()
    return {"tool_ids": sorted(valid_ids)}
