"""
PluginLoader – erkennt und lädt Provider- und Tool-Plugins automatisch.

Beim Start scannt das System zwei Ordner:
1. providers/ – alle Python-Dateien die BaseProvider implementieren
2. tools/      – alle Python-Dateien die BaseTool implementieren

Dateien mit _ am Anfang und base.py werden übersprungen.
Eigene Plugins in plugins/providers/ und plugins/tools/ ablegen
(via Docker-Volume gemountet, kein Image-Rebuild nötig).
"""

import importlib.util
import inspect
import logging
from pathlib import Path
from typing import Dict, List, Optional, Type

from providers.base import BaseProvider
from tools.base import BaseTool

logger = logging.getLogger(__name__)

# Globale Registries
PROVIDER_REGISTRY: Dict[str, Type[BaseProvider]] = {}
TOOL_CLASS_REGISTRY: Dict[str, Type[BaseTool]] = {}


def _load_module_from_file(file_path: Path, module_name: str):
    """Lädt ein Python-Modul aus einer Datei."""
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_providers(extra_dirs: Optional[List[Path]] = None) -> Dict[str, Type[BaseProvider]]:
    """
    Scannt Provider-Verzeichnisse und registriert alle gefundenen BaseProvider-Subklassen.

    Reihenfolge:
    1. providers/ (eingebaute Provider)
    2. extra_dirs (Plugin-Verzeichnisse, z.B. plugins/providers/)
    """
    base_providers_dir = Path(__file__).parent.parent / "providers"
    dirs_to_scan = [base_providers_dir] + (extra_dirs or [])

    for providers_dir in dirs_to_scan:
        if not providers_dir.exists():
            continue

        for py_file in sorted(providers_dir.glob("*.py")):
            if py_file.name.startswith("_") or py_file.name == "base.py":
                continue

            module_name = f"providers.{py_file.stem}"
            try:
                module = _load_module_from_file(py_file, module_name)
                if module is None:
                    continue

                for attr_name in dir(module):
                    attr = getattr(module, attr_name)
                    if (
                        inspect.isclass(attr)
                        and issubclass(attr, BaseProvider)
                        and attr is not BaseProvider
                        and hasattr(attr, "name")
                        and attr.name != "base"
                    ):
                        PROVIDER_REGISTRY[attr.name] = attr
                        logger.info(f"Provider geladen: {attr.name} ({attr.display_name})")

            except Exception as e:
                logger.error(f"Fehler beim Laden von Provider {py_file}: {e}")

    return PROVIDER_REGISTRY


def load_tool_classes(extra_dirs: Optional[List[Path]] = None) -> Dict[str, Type[BaseTool]]:
    """
    Scannt Tool-Verzeichnisse und registriert alle BaseTool-Subklassen.
    Diese werden bei Bedarf instanziiert (nicht hier).
    """
    base_tools_dir = Path(__file__).parent.parent / "tools"
    dirs_to_scan = [base_tools_dir] + (extra_dirs or [])

    for tools_dir in dirs_to_scan:
        if not tools_dir.exists():
            continue

        for py_file in sorted(tools_dir.glob("*.py")):
            if py_file.name.startswith("_") or py_file.name == "base.py":
                continue

            module_name = f"tools.{py_file.stem}"
            try:
                module = _load_module_from_file(py_file, module_name)
                if module is None:
                    continue

                for attr_name in dir(module):
                    attr = getattr(module, attr_name)
                    if (
                        inspect.isclass(attr)
                        and issubclass(attr, BaseTool)
                        and attr is not BaseTool
                        and hasattr(attr, "name")
                        and attr.name not in ("base_tool",)
                    ):
                        TOOL_CLASS_REGISTRY[attr.name] = attr
                        logger.info(f"Tool-Klasse geladen: {attr.name}")

            except Exception as e:
                logger.error(f"Fehler beim Laden von Tool {py_file}: {e}")

    return TOOL_CLASS_REGISTRY


def get_provider(provider_type: str, config: dict) -> Optional[BaseProvider]:
    """Erstellt eine Provider-Instanz aus dem Registry."""
    provider_class = PROVIDER_REGISTRY.get(provider_type)
    if provider_class is None:
        logger.error(f"Unbekannter Provider-Typ: {provider_type}")
        return None
    return provider_class(config)


def list_available_providers() -> List[Dict]:
    """Gibt alle registrierten Provider als Dict-Liste zurück."""
    return [
        {"name": cls.name, "display_name": cls.display_name}
        for cls in PROVIDER_REGISTRY.values()
    ]
