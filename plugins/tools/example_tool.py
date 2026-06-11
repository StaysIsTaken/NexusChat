"""
Beispiel: Eigenes Tool als Plugin.

Diese Datei demonstriert wie ein eigenes Tool erstellt wird.
In plugins/tools/ ablegen → automatische Erkennung beim Backend-Start.

Dieses Beispiel implementiert ein einfaches Taschenrechner-Tool.
"""

from tools.base import BaseTool, ToolParameter
from typing import Any, Dict


class CalculatorTool(BaseTool):
    """
    Taschenrechner-Tool – einfache mathematische Ausdrücke auswerten.
    Demonstriert die BaseTool-Implementierung.
    """

    name = "calculator"
    description = "Wertet einen mathematischen Ausdruck aus und gibt das Ergebnis zurück"
    parameters = {
        "expression": ToolParameter(
            type="string",
            description="Mathematischer Ausdruck, z.B. '2 + 3 * 4'",
            required=True,
        )
    }

    async def execute(self, arguments: Dict[str, Any]) -> str:
        expression = arguments.get("expression", "")

        # Nur sichere Operationen erlauben (keine eval-Injection)
        allowed_chars = set("0123456789+-*/().^ ")
        if not all(c in allowed_chars for c in expression):
            return f"Fehler: Ungültige Zeichen im Ausdruck: {expression}"

        try:
            # Potenz-Operator ^ → ** konvertieren
            safe_expr = expression.replace("^", "**")
            result = eval(safe_expr, {"__builtins__": {}}, {})  # noqa: S307
            return f"{expression} = {result}"
        except Exception as e:
            return f"Fehler beim Auswerten von '{expression}': {str(e)}"
