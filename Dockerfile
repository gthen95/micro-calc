# =============================================================================
# micro-calc — Dockerfile multi-stage
# Reto 5 — Diplomado de Arquitectura de Software (Modulo 5)
#
# Objetivo: construir la imagen SIN depender de Java ni Maven instalados en el
# host. En esta maquina hay java 17 y NO hay mvn; el proyecto exige JDK 21 y
# Maven 3.9+. La etapa `build` resuelve ambas cosas dentro del contenedor.
# =============================================================================

# -----------------------------------------------------------------------------
# ARG GLOBALES — deben declararse ANTES del primer FROM
# -----------------------------------------------------------------------------
# Un ARG solo es visible en el FROM que lo usa si esta declarado en el ambito
# global (antes de cualquier FROM). Declararlo dentro de una etapa NO sirve:
# BuildKit avisa con "UndefinedArgInFrom" y la base queda vacia.
#
# Tamanos MEDIDOS el 2026-08-21 en este equipo:
#   mcr.microsoft.com/openjdk/jdk:21-ubuntu (JDK) -> 213 MB base -> 221 MB final
#   eclipse-temurin:21-jre-jammy            (JRE) ->  99 MB base -> 117 MB final
# Se elige MCR por defecto: registro sin rate limit ni login obligatorio.
# Para priorizar tamano de imagen:
#   docker build --build-arg RUNTIME_IMAGE=eclipse-temurin:21-jre-jammy .
ARG BUILD_IMAGE=maven:3.9-eclipse-temurin-21
ARG RUNTIME_IMAGE=mcr.microsoft.com/openjdk/jdk:21-ubuntu

# -----------------------------------------------------------------------------
# ETAPA 1 — build: compila el JAR con JDK 21 + Maven 3.9
# -----------------------------------------------------------------------------
# Se usa `maven:3.9-eclipse-temurin-21` porque Microsoft Artifact Registry (MCR)
# NO publica una imagen con Maven preinstalado. Verificado el 2026-08-21: la
# imagen se descarga de forma anonima desde Docker Hub (no exige `docker login`)
# en esta red. Si en otra red apareciera el rate limit anonimo de Docker Hub
# (100 pulls / 6 h por IP), basta con hacer `docker login` antes del build.
# Parametrizable: docker build --build-arg BUILD_IMAGE=... .
FROM ${BUILD_IMAGE} AS build

# --- Soporte de proxy corporativo (inerte si no se pasan los ARG) ------------
# En este entorno NO hay proxy (verificado en docs/00-entorno.md), pero se dejan
# los ARG para que el Dockerfile sea portable a una red que si lo tenga:
#   docker build --build-arg HTTP_PROXY=http://proxy:8080 ... .
ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG NO_PROXY=""
ARG MAVEN_OPTS=""
ENV HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    http_proxy=${HTTP_PROXY} \
    https_proxy=${HTTPS_PROXY} \
    no_proxy=${NO_PROXY} \
    MAVEN_OPTS=${MAVEN_OPTS}

WORKDIR /build

# --- CA corporativa de inspeccion TLS (deep inspection) ----------------------
# La red donde se construye esta imagen tiene un FortiGate interceptando TLS de
# forma SELECTIVA. Verificado el 2026-08-21: repo.maven.apache.org, auth.docker.io,
# github.com y ghcr.io presentan certificados reemitidos por `O=Fortinet`;
# registry-1.docker.io, mcr.microsoft.com, registry.k8s.io y gcr.io NO.
#
# Windows y la distro WSL2 de Rancher Desktop SI confian en esa CA (por eso
# `docker pull` funciona), pero ESTE contenedor trae su propio truststore: el
# `cacerts` de la JVM. Sin importar la CA, Maven aborta con:
#     PKIX path building failed: unable to find valid certification path
#
# La carpeta certs/ siempre existe (lleva un .gitkeep) pero su contenido *.crt
# esta en .gitignore: no se publica en el fork. Se genera localmente con
# scripts/00-extraer-ca-corporativa.ps1. Si esta vacia -por ejemplo fuera de la
# red corporativa- el bloque no hace nada y el build sigue siendo portable.
COPY certs/ /opt/corp-ca/
RUN set -eu; \
    n=$(ls -1 /opt/corp-ca/*.crt 2>/dev/null | wc -l || true); \
    if [ "$n" -gt 0 ]; then \
        echo "[CA] Importando $n certificado(s) de CA corporativa..."; \
        cp /opt/corp-ca/*.crt /usr/local/share/ca-certificates/; \
        update-ca-certificates; \
        for f in /opt/corp-ca/*.crt; do \
            keytool -importcert -noprompt -trustcacerts \
                    -alias "corp-$(basename "$f" .crt)" \
                    -file "$f" -cacerts -storepass changeit > /dev/null 2>&1 || true; \
        done; \
        echo "[CA] Truststore del SO y de la JVM actualizados."; \
    else \
        echo "[CA] Sin CA corporativa en certs/: se usa el truststore por defecto."; \
    fi

# --- Cache de dependencias --------------------------------------------------
# Se copia PRIMERO solo el pom.xml y se resuelven las dependencias. Docker
# cachea esta capa: mientras el pom no cambie, un rebuild tras tocar el codigo
# tarda segundos en vez de minutos, porque no vuelve a bajar Maven Central.
# NO se usa el ./mvnw del repositorio: su wrapper apunta a Maven 3.8.6 y
# Spring Boot 4.1.0 exige Maven 3.9+. Se usa el `mvn` de la imagen base.
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline

# --- Compilacion ------------------------------------------------------------
# Ahora si el codigo fuente. Cualquier cambio aqui invalida solo esta capa.
COPY src ./src

# Se ejecutan los tests (DemoMicroApplicationTests.contextLoads) a proposito:
# validan que el contexto de Spring levanta con las propiedades del
# application.properties empaquetado. Si se quisiera omitir: -DskipTests.
# El artefacto es demo-micro-0.0.1-SNAPSHOT.jar. Se renombra a app.jar para NO
# acoplar la etapa de runtime al numero de version del pom.
RUN mvn -B -ntp clean package \
    && cp target/demo-micro-*.jar /build/app.jar \
    && ls -lh /build/app.jar

# -----------------------------------------------------------------------------
# ETAPA 2 — runtime: solo lo necesario para ejecutar
# -----------------------------------------------------------------------------
# Imagen base de Microsoft Artifact Registry (mcr.microsoft.com): no aplica el
# rate limit de Docker Hub y no requiere autenticacion. Verificado disponible.
# Nota documentada en docs/DECISIONES.md: MCR publica JDK, no JRE; a cambio de
# ~150 MB extra se gana un registro sin rate limit ni login.
# Alternativa si se prioriza el tamano: eclipse-temurin:21-jre-jammy
# Parametrizable. Tamanos MEDIDOS el 2026-08-21 en este equipo:
#   mcr.microsoft.com/openjdk/jdk:21-ubuntu  -> 213 MB base -> 221 MB imagen final
#   eclipse-temurin:21-jre-jammy             ->  99 MB base -> 117 MB imagen final
# Se elige MCR por defecto (registro sin rate limit ni login). Para priorizar
# tamano:  docker build --build-arg RUNTIME_IMAGE=eclipse-temurin:21-jre-jammy .
FROM ${RUNTIME_IMAGE} AS runtime

# --- Endurecimiento: usuario no-root ----------------------------------------
# UID/GID fijos 10001. El securityContext del Deployment usa runAsNonRoot: true,
# que EXIGE que la imagen declare un UID numerico distinto de 0; si se dejara
# root, el kubelet rechazaria el Pod con CreateContainerConfigError.
RUN groupadd --system --gid 10001 spring \
    && useradd --system --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin spring

WORKDIR /app

# Se copia unicamente el JAR: ni el codigo fuente, ni el repositorio ~/.m2,
# ni Maven llegan a la imagen final.
COPY --from=build --chown=10001:10001 /build/app.jar /app/app.jar

USER 10001:10001

EXPOSE 8080

# --- Metadatos OCI ----------------------------------------------------------
LABEL org.opencontainers.image.title="micro-calc" \
      org.opencontainers.image.description="Microservicio calculadora Spring Boot - Reto 5 Diplomado de Arquitectura" \
      org.opencontainers.image.source="https://github.com/gthen95/micro-calc" \
      org.opencontainers.image.licenses="MIT"

# --- Arranque ---------------------------------------------------------------
# Exec form (sin shell): el proceso java queda como PID 1 y recibe SIGTERM
# directamente, por lo que Spring hace shutdown ordenado cuando Kubernetes
# termina el Pod. Con shell form, `sh` seria PID 1 y se tragaria la senal.
#
# -XX:MaxRAMPercentage=75  ->  la JVM calcula su heap sobre el LIMITE DEL
# CONTENEDOR (512Mi en el Deployment), no sobre los 63 GB del host. Sin este
# flag la JVM reservaria heap segun la RAM de la maquina, se pasaria del limit
# y el kernel mataria el Pod con OOMKilled. Es el error clasico de Java en K8s.
#
# NO se define HEALTHCHECK: la imagen base no trae curl ni wget, y en Kubernetes
# el HEALTHCHECK de Docker se ignora — quien decide salud son los probes del
# Deployment (readiness / liveness / startup).
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "-jar", "/app/app.jar"]
