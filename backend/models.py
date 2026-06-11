"""
Datenbank-Modelle (SQLite via SQLAlchemy async).

Tabellen:
- providers:    Konfigurierte KI-Provider (Ollama, OpenAI, etc.)
- tool_servers: Konfigurierte Tool-Server (MCP, REST, Custom)
- chats:        Gesprächsverläufe
- messages:     Einzelne Nachrichten in einem Gespräch
- settings:     App-Einstellungen (Key-Value)
"""

import os
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    Boolean, Column, DateTime, ForeignKey, JSON, String, Text
)
from sqlalchemy.ext.asyncio import (
    AsyncSession, async_sessionmaker, create_async_engine
)
from sqlalchemy.orm import DeclarativeBase, relationship

# Datenbank-Datei im /data Verzeichnis (als Docker-Volume gemountet)
_DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
os.makedirs(_DATA_DIR, exist_ok=True)
DATABASE_URL = f"sqlite+aiosqlite:///{os.path.join(_DATA_DIR, 'nexuschat.db')}"

engine = create_async_engine(DATABASE_URL, echo=False)
async_session_maker = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class Provider(Base):
    __tablename__ = "providers"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, nullable=False)
    type = Column(String, nullable=False)        # ollama | openai | anthropic | openai_compatible
    base_url = Column(String, nullable=True)
    api_key = Column(String, nullable=True)
    default_model = Column(String, nullable=True)
    custom_headers = Column(JSON, default=lambda: {})
    is_enabled = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    chats = relationship("Chat", back_populates="provider")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "type": self.type,
            "base_url": self.base_url,
            "api_key": self.api_key,       # Frontend zeigt nur ob vorhanden, nicht den Wert
            "default_model": self.default_model,
            "custom_headers": self.custom_headers or {},
            "is_enabled": self.is_enabled,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class ToolServer(Base):
    __tablename__ = "tool_servers"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, nullable=False)
    type = Column(String, nullable=False)        # mcp | rest | custom
    url = Column(String, nullable=True)          # Endpunkt-URL
    api_key = Column(String, nullable=True)
    config = Column(JSON, default=lambda: {})    # Typ-spezifische Konfiguration
    is_enabled = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "type": self.type,
            "url": self.url,
            "api_key": self.api_key,
            "config": self.config or {},
            "is_enabled": self.is_enabled,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class Chat(Base):
    __tablename__ = "chats"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    title = Column(String, default="Neues Gespräch")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    provider_id = Column(String, ForeignKey("providers.id"), nullable=True)
    model_name = Column(String, nullable=True)
    active_tool_ids = Column(JSON, default=lambda: [])  # Liste von ToolServer-IDs
    system_prompt = Column(Text, nullable=True)

    provider = relationship("Provider", back_populates="chats")
    messages = relationship(
        "Message",
        back_populates="chat",
        order_by="Message.timestamp",
        cascade="all, delete-orphan",
    )

    def to_dict(self, include_messages: bool = False) -> dict:
        d = {
            "id": self.id,
            "title": self.title,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "provider_id": self.provider_id,
            "model_name": self.model_name,
            "active_tool_ids": self.active_tool_ids or [],
            "system_prompt": self.system_prompt,
        }
        if include_messages:
            d["messages"] = [m.to_dict() for m in self.messages]
        return d


class Message(Base):
    __tablename__ = "messages"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    chat_id = Column(String, ForeignKey("chats.id"), nullable=False)
    role = Column(String, nullable=False)        # user | assistant | system
    content = Column(Text, nullable=False, default="")
    timestamp = Column(DateTime, default=datetime.utcnow)
    tool_calls = Column(JSON, default=lambda: [])    # Aufgezeichnete Tool-Aufrufe
    tool_results = Column(JSON, default=lambda: [])  # Aufgezeichnete Tool-Ergebnisse

    chat = relationship("Chat", back_populates="messages")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "chat_id": self.chat_id,
            "role": self.role,
            "content": self.content,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None,
            "tool_calls": self.tool_calls or [],
            "tool_results": self.tool_results or [],
        }


class Settings(Base):
    __tablename__ = "settings"

    key = Column(String, primary_key=True)
    value = Column(Text, nullable=True)


async def init_db():
    """Erstellt alle Tabellen falls sie nicht existieren."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncSession:
    """FastAPI Dependency – liefert eine Datenbankverbindung."""
    async with async_session_maker() as session:
        yield session
