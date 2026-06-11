FROM python:3.11-slim

WORKDIR /app

# Abhängigkeiten zuerst (Docker Layer Caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Quellcode kopieren
COPY . .

# Daten-Verzeichnis für SQLite
RUN mkdir -p /app/data

# Plugin-Verzeichnisse (werden als Volumes gemountet)
RUN mkdir -p /app/providers/custom /app/tools/custom

EXPOSE 8099

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8099", "--workers", "1"]
