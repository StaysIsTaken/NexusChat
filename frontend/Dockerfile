# Stage 1: Flutter Web Build
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
# Web-Release Build
RUN flutter build web --release --base-href /

# Stage 2: nginx für statische Dateien + Proxy
FROM nginx:alpine

# Flutter-Build-Output nach nginx kopieren
COPY --from=builder /app/build/web /usr/share/nginx/html

# Nginx-Konfiguration (Proxy zu Backend)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
