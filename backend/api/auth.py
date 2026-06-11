"""
Auth-API – Registrierung des Admins, Login und Profil.

Endpoints:
  GET  /api/auth/status   – Muss noch ein Admin angelegt werden?
  POST /api/auth/setup    – Einmalige Admin-Registrierung (nur wenn kein Admin existiert)
  POST /api/auth/login    – Anmeldung, gibt JWT zurück
  GET  /api/auth/me       – Aktueller Nutzer (erfordert Token)
"""

import logging
import time
from collections import defaultdict

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

# ── Brute-Force-Schutz für Login (in-memory) ─────────────────────────────────
_MAX_ATTEMPTS = 8
_WINDOW_SECONDS = 300  # 5 Minuten
_login_attempts: dict[str, list[float]] = defaultdict(list)


def _check_rate_limit(key: str) -> None:
    now = time.monotonic()
    attempts = [t for t in _login_attempts[key] if now - t < _WINDOW_SECONDS]
    _login_attempts[key] = attempts
    if len(attempts) >= _MAX_ATTEMPTS:
        raise HTTPException(
            429, "Zu viele Login-Versuche. Bitte warte ein paar Minuten."
        )


def _record_attempt(key: str) -> None:
    _login_attempts[key].append(time.monotonic())


def _reset_attempts(key: str) -> None:
    _login_attempts.pop(key, None)


class Credentials(BaseModel):
    username: str
    password: str


class PasswordChange(BaseModel):
    current_password: str
    new_password: str


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
    username = data.username.strip()
    _check_rate_limit(username)

    result = await db.execute(select(User).where(User.username == username))
    user = result.scalar_one_or_none()
    if user is None or not verify_password(data.password, user.password_hash):
        _record_attempt(username)
        raise HTTPException(401, "Benutzername oder Passwort falsch.")

    _reset_attempts(username)
    secret = await get_jwt_secret(db)
    token = create_token(secret, user)
    return {"token": token, "user": user.to_dict()}


@router.get("/me")
async def me(user: User = Depends(get_current_user)):
    return user.to_dict()


@router.put("/password")
async def change_own_password(
    data: PasswordChange,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
):
    """Eigenes Passwort ändern (auch zum Erfüllen eines erzwungenen Wechsels)."""
    if not verify_password(data.current_password, user.password_hash):
        raise HTTPException(403, "Aktuelles Passwort ist falsch.")
    if len(data.new_password) < 4:
        raise HTTPException(400, "Neues Passwort ist zu kurz.")

    user.password_hash = hash_password(data.new_password)
    user.must_change_password = False
    await db.commit()
    await db.refresh(user)

    # Frisches Token ausstellen (Rolle/Flag könnten sich geändert haben)
    secret = await get_jwt_secret(db)
    token = create_token(secret, user)
    return {"token": token, "user": user.to_dict()}
