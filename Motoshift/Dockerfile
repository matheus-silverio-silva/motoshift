# syntax=docker/dockerfile:1

# ──────────────────────────────────────────────────────────────────────────────
# Estágio 1 — Build do Flutter web
# ──────────────────────────────────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS build

# URL base da API, injetada em build-time.
# No Railway, defina a variável de ambiente API_URL no serviço — ela é repassada
# automaticamente como build arg para o Dockerfile.
# Ex.: API_URL=https://motoshift-backend.up.railway.app
ARG API_URL=""

WORKDIR /app

# Resolve dependências primeiro (camada cacheável enquanto o pubspec não muda).
COPY pubspec.yaml ./
RUN flutter pub get

# Copia o restante do código e gera o build de produção.
COPY . .
RUN flutter build web --release --dart-define=API_URL=$API_URL

# ──────────────────────────────────────────────────────────────────────────────
# Estágio 2 — Servir com nginx
# ──────────────────────────────────────────────────────────────────────────────
FROM nginx:stable-alpine AS runtime

# A imagem oficial do nginx processa templates em /etc/nginx/templates com
# envsubst no entrypoint, gerando /etc/nginx/conf.d/default.conf. Isso permite
# escutar na porta definida por $PORT (Railway injeta uma dinâmica; default 80).
COPY nginx.conf /etc/nginx/templates/default.conf.template

COPY --from=build /app/build/web /usr/share/nginx/html

ENV PORT=80
EXPOSE 80
