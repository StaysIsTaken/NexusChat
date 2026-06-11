"""
Verschlüsselung sensibler Werte (Provider-/Tool-API-Keys) at rest.

Nutzt Fernet (AES-128-CBC + HMAC). Der Schlüssel wird deterministisch aus dem
ebenfalls in der DB gespeicherten JWT-Secret abgeleitet – kein zusätzliches
Geheimnis nötig. Optional kann mit der Umgebungsvariable NEXUS_SECRET_KEY ein
eigener Schlüssel vorgegeben werden.

Gespeicherte Werte tragen das Präfix "enc::". Werte ohne Präfix gelten als
Klartext (Altbestand) und werden beim nächsten Speichern automatisch verschlüsselt.
"""

import base64
import hashlib
import os
from typing import Optional

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.ext.asyncio import AsyncSession

_PREFIX = "enc::"
_cipher: Optional[Fernet] = None


async def _get_cipher(db: AsyncSession) -> Fernet:
    global _cipher
    if _cipher is not None:
        return _cipher

    raw = os.environ.get("NEXUS_SECRET_KEY")
    if not raw:
        # Aus dem JWT-Secret ableiten (liegt bereits in der DB)
        from core.auth import get_jwt_secret
        raw = await get_jwt_secret(db)

    key = base64.urlsafe_b64encode(hashlib.sha256(raw.encode("utf-8")).digest())
    _cipher = Fernet(key)
    return _cipher


async def encrypt_secret(db: AsyncSession, plaintext: Optional[str]) -> Optional[str]:
    """Verschlüsselt einen Wert. Leere Werte bleiben unverändert."""
    if not plaintext:
        return plaintext
    if plaintext.startswith(_PREFIX):
        return plaintext  # bereits verschlüsselt
    cipher = await _get_cipher(db)
    token = cipher.encrypt(plaintext.encode("utf-8")).decode("utf-8")
    return _PREFIX + token


async def decrypt_secret(db: AsyncSession, stored: Optional[str]) -> Optional[str]:
    """Entschlüsselt einen gespeicherten Wert. Klartext (ohne Präfix) wird durchgereicht."""
    if not stored:
        return stored
    if not stored.startswith(_PREFIX):
        return stored  # Altbestand im Klartext
    cipher = await _get_cipher(db)
    try:
        return cipher.decrypt(stored[len(_PREFIX):].encode("utf-8")).decode("utf-8")
    except InvalidToken:
        return ""
