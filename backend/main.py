"""
NexusChat Backend – FastAPI Hauptdatei.

Startet den Server, initialisiert die Datenbank und lädt alle Plugins.

Entwicklung:
    uvicorn main:app --reload --port 8099

Produktion (Docker):
    uvicorn main:app --host 0.0.0.0 --port 8099 --workers 1
"""

import logging
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Pfad-Setup damit relative Imports funktionieren
sys.path.insert(0, str(Path(__file__).parent))

from models import init_db
from core.plugin_loader import load_providers, load_tool_classes, PROVIDER_REGISTRY
from api.chat import router as chat_router
from api.providers import router as providers_router
from api.tools import router as tools_router
from api.settings import router as settings_router
from api.auth import router as auth_router
from api.users import router as users_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/Shutdown Lifecycle."""

    # Datenbank initialisieren
    logger.info("Initialisiere Datenbank...")
    await init_db()
    logger.info("Datenbank bereit.")

    # Plugins laden – Custom-Verzeichnisse aus Umgebungsvariablen
    custom_providers_dir = os.environ.get("CUSTOM_PROVIDERS_DIR")
    custom_tools_dir = os.environ.get("CUSTOM_TOOLS_DIR")

    extra_provider_dirs = [Path(custom_providers_dir)] if custom_providers_dir else []
    extra_tool_dirs = [Path(custom_tools_dir)] if custom_tools_dir else []

    logger.info("Lade Provider-Plugins...")
    load_providers(extra_dirs=extra_provider_dirs)
    logger.info(f"Registrierte Provider: {list(PROVIDER_REGISTRY.keys())}")

    logger.info("Lade Tool-Plugins...")
    load_tool_classes(extra_dirs=extra_tool_dirs)

    logger.info("NexusChat Backend bereit.")
    yield

    logger.info("NexusChat Backend wird beendet.")


app = FastAPI(
    title="NexusChat API",
    description="Universelle, erweiterbare KI-Chat-API",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS – Frontend-Zugriff erlauben
# In Produktion auf die tatsächliche Frontend-URL einschränken
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Router registrieren
app.include_router(auth_router)
app.include_router(users_router)
app.include_router(chat_router)
app.include_router(providers_router)
app.include_router(tools_router)
app.include_router(settings_router)


@app.get("/health")
async def health_check():
    """Liveness-Probe für Docker/Kubernetes."""
    return {
        "status": "ok",
        "providers": list(PROVIDER_REGISTRY.keys()),
    }
