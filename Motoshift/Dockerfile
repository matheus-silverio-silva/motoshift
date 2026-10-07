# syntax=docker/dockerfile:1

# ──────────────────────────────────────────────────────────────────────────────
# Estágio 1 — Build do Flutter web
# ──────────────────────────────────────────────────────────────────────────────
# Versao FIXA do Flutter, a mesma do CI (.github/workflows/ci.yml) e a mesma
# com que os goldens foram gravados. Com `:stable` a imagem era a do dia do
# deploy: o mesmo commit gerava um app diferente conforme a data do build, e
# um stable novo podia quebrar a publicacao sem ninguem ter mexido no codigo.
# Subir esta versao e uma mudanca de proposito, feita junto com a do CI.
FROM ghcr.io/cirruslabs/flutter:3.41.5 AS build

# URL base da API, injetada em build-time.
# No Railway, defina a variável de ambiente API_URL no serviço — ela é repassada
# automaticamente como build arg para o Dockerfile.
# Ex.: API_URL=https://motoshift-backend.up.railway.app
ARG API_URL=""

WORKDIR /app

# Resolve dependências primeiro (camada cacheável enquanto o pubspec e o lock
# não mudam). O pubspec.lock vai junto: é ele que diz QUAIS versões — sem ele o
# `pub get` escolheria as mais novas que o pubspec.yaml aceita. O
# `--enforce-lockfile` faz o build falhar se o lock não bater com o pubspec, em
# vez de resolver de novo em silêncio.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile

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
