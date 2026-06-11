"""
Auth-Kern – Passwort-Hashing, JWT und FastAPI-Dependencies.

Token-Fluss:
- Login/Setup gibt ein JWT (HS256) zurück: {"sub": user_id, "role": ..., "exp": ...}
- REST-Aufrufe schicken es als `Authorization: Bearer <token>`
- WebSocket schickt es als Query-Parameter `?token=<token>` (Header sind dort umständlich)

Das JWT-Secret wird einmalig generiert und in der Settings-Tabelle gespeichert.
"""

import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import Settings, User, get_session, user_providers, user_tools

logger = logging.getLogger(__name__)

_ALGORITHM = "HS256"
_TOKEN_TTL_DAYS = 30
_SECRET_KEY_NAME = "jwt_secret"

# Secret wird nach dem ersten Laden gecached
_cached_secret: Optional[str] = None


# ── Passwörter ───────────────────────────────────────────────────────────────

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except Exception:
        return False


# ── JWT-Secret ───────────────────────────────────────────────────────────────

async def get_jwt_secret(db: AsyncSession) -> str:
    """Lädt das JWT-Secret aus der DB – erzeugt es beim ersten Mal."""
    global _cached_secret
    if _cached_secret:
        return _cached_secret

    existing = await db.get(Settings, _SECRET_KEY_NAME)
    if existing and existing.value:
        _cached_secret = existing.value
        return _cached_secret

    # Neu erzeugen und persistieren
    new_secret = secrets.token_hex(32)
    db.add(Settings(key=_SECRET_KEY_NAME, value=new_secret))
    await db.commit()
    _cached_secret = new_secret
    logger.info("Neues JWT-Secret generiert und gespeichert.")
    return _cached_secret


# ── Token erstellen/prüfen ────────────────────────────────────────────────────

def create_token(secret: str, user: User) -> str:
    payload = {
        "sub": user.id,
        "username": user.username,
        "role": user.role,
        "exp": datetime.utcnow() + timedelta(days=_TOKEN_TTL_DAYS),
    }
    return jwt.encode(payload, secret, algorithm=_ALGORITHM)


def _decode(token: str, secret: str) -> Optional[dict]:
    try:
        return jwt.decode(token, secret, algorithms=[_ALGORITHM])
    except jwt.PyJWTError:
        return None


async def authenticate_token(token: str, db: AsyncSession) -> Optional[User]:
    """Token validieren und zugehörigen User laden. Für REST und WebSocket."""
    secret = await get_jwt_secret(db)
    payload = _decode(token, secret)
    if not payload:
        return None
    user_id = payload.get("sub")
    if not user_id:
        return None
    return await db.get(User, user_id)


# ── FastAPI-Dependencies ──────────────────────────────────────────────────────

_bearer = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: AsyncSession = Depends(get_session),
) -> User:
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Nicht angemeldet",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user = await authenticate_token(credentials.credentials, db)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Ungültiges oder abgelaufenes Token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


async def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Nur der Administrator darf das.",
        )
    return user


# ── Zugriffszuweisungen ───────────────────────────────────────────────────────

async def user_provider_ids(db: AsyncSession, user_id: str) -> set:
    rows = await db.execute(
        select(user_providers.c.provider_id).where(user_providers.c.user_id == user_id)
    )
    return {r[0] for r in rows.all()}


async def user_tool_ids(db: AsyncSession, user_id: str) -> set:
    rows = await db.execute(
        select(user_tools.c.tool_server_id).where(user_tools.c.user_id == user_id)
    )
    return {r[0] for r in rows.all()}


async def can_use_provider(db: AsyncSession, user: User, provider_id: str) -> bool:
    if user.role == "admin":
        return True
    return provider_id in await user_provider_ids(db, user.id)


async def can_use_tool(db: AsyncSession, user: User, tool_id: str) -> bool:
    if user.role == "admin":
        return True
    return tool_id in await user_tool_ids(db, user.id)
