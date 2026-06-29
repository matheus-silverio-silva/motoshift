# ── Build stage ──────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
ARG API_URL
RUN flutter build web --dart-define=API_URL=$API_URL --release

# ── Serve stage ──────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app
COPY --from=build /app/build/web ./build/web

CMD python3 -m http.server ${PORT:-8080} --directory build/web
