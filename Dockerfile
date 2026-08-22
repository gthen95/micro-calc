ARG BUILD_IMAGE=maven:3.9-eclipse-temurin-21
ARG RUNTIME_IMAGE=mcr.microsoft.com/openjdk/jdk:21-ubuntu

FROM ${BUILD_IMAGE} AS build

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

COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline

COPY src ./src

RUN mvn -B -ntp clean package \
    && cp target/demo-micro-*.jar /build/app.jar \
    && ls -lh /build/app.jar

FROM ${RUNTIME_IMAGE} AS runtime

RUN groupadd --system --gid 10001 spring \
    && useradd --system --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin spring

WORKDIR /app

COPY --from=build --chown=10001:10001 /build/app.jar /app/app.jar

USER 10001:10001

EXPOSE 8080

LABEL org.opencontainers.image.title="micro-calc" \
      org.opencontainers.image.description="Microservicio calculadora Spring Boot - Reto 5 Diplomado de Arquitectura" \
      org.opencontainers.image.source="https://github.com/gthen95/micro-calc" \
      org.opencontainers.image.licenses="MIT"

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "-jar", "/app/app.jar"]
