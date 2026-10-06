# syntax=docker/dockerfile:1

# ──────────────────────────────────────────────────────────────────────────────
# Estágio 1 — Build do Spring Boot com Maven
# ──────────────────────────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Dependências primeiro (camada cacheável enquanto o pom.xml não muda).
COPY pom.xml ./
RUN mvn -q -B dependency:go-offline

COPY src ./src
RUN mvn -q -B clean package -DskipTests

# ──────────────────────────────────────────────────────────────────────────────
# Estágio 2 — Runtime só com a JRE
# ──────────────────────────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre
WORKDIR /app

COPY --from=build /app/target/*.jar app.jar

# Mesmo perfil que o railway.json usava no startCommand.
ENV SPRING_PROFILES_ACTIVE=prod

# O Render injeta PORT; o application-prod.properties já lê ${PORT:8080}.
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
