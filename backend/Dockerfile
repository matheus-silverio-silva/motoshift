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

# Fuso de Curitiba (SCRUM-48). O container do Render roda em UTC, três horas à
# frente: sem isto as regras que comparam a data do turno com o "agora" do
# servidor saem deslocadas. O MotoshiftApplication também define o fuso no
# main (variável MOTOSHIFT_FUSO, mesmo padrão); o TZ e o -Duser.timezone
# abaixo fazem a JVM já nascer nele, antes do main.
ENV TZ=America/Sao_Paulo

# O Render injeta PORT; o application-prod.properties já lê ${PORT:8080}.
EXPOSE 8080

ENTRYPOINT ["java", "-Duser.timezone=America/Sao_Paulo", "-jar", "app.jar"]
