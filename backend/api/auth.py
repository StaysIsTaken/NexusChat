"""
Auth-API – Registrierung des Admins, Login und Profil.

Endpoints:
  GET  /api/auth/status   – Muss noch ein Admin angelegt werden?
  POST /api/auth/setup    – Einmalige Admin-Registrierung (nur wenn kein Admin existiert)
  POST /api/auth/login    – Anmeldung, gibt JWT zurück
  GET  /api/auth/me       – Aktueller Nutzer (erfordert Token)
"""

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from models import Chat, User, get_session
from core.auth import (
    create_token,
    get_current_user,
    get_jwt_secret,
    hash_password,
    verify_password,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["auth"])


class Credentials(BaseModel):
    username: str
    password: str


async def _admin_exists(db: AsyncSession) -> bool:
    result = await db.execute(select(User).where(User.role == "admin").limit(1))
    return result.scalar_one_or_none() is not None


@router.get("/status")
async def auth_status(db: AsyncSession = Depends(get_session)):
    """Sagt dem Frontend ob die einmalige Admin-Einrichtung nötig ist."""
    return {"needs_setup": not await _admin_exists(db)}


@router.post("/setup", status_code=201)
async def setup_admin(data: Credentials, db: AsyncSession = Depends(get_session)):
    """Legt den ersten Admin an – nur möglich solange keiner existiert."""
    if await _admin_exists(db):
        raise HTTPException(403, "Es existiert bereits ein Administrator.")

    username = data.username.strip()
    if not username or not data.password:
        raise HTTPException(400, "Benutzername und Passwort erforderlich.")

    admin = User(
        username=username,
        password_hash=hash_password(data.password),
        role="admin",
    )
    db.add(admin)
    await db.commit()
    await db.refresh(admin)

    # Bestehende Chats ohne Besitzer dem Admin zuordnen (Daten nicht verlieren)
    await db.execute(
        update(Chat).where(Chat.user_id.is_(None)).values(user_id=admin.id)
    )
    await db.commit()

    secret = await get_jwt_secret(db)
    token = create_token(secret, admin)
    logger.info(f"Admin '{username}' eingerichtet.")
    return {"token": token, "user": admin.to_dict()}


@router.post("/login")
async def login(data: Credentials, db: AsyncSession = Depends(get_session)):
    result = await db.execute(select(User).where(User.username == data.username.strip()))
    user = result.scalar_one_or_none()
    if user is None or not verify_password(data.password, user.password_hash):
        raise HTTPException(401, "Benutzername oder Passwort falsch.")

    secret = await get_jwt_secret(db)
    token = create_token(secret, user)
    return {"token": token, "user": user.to_dict()}


@router.get("/me")
async def me(user: User = Depends(get_current_user)):
    return user.to_dict()
