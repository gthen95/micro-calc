# FASE 0 — Diagnóstico del entorno

**Fecha de ejecución:** 2026-08-21
**Equipo:** Microsoft Windows 11 Enterprise (build 10.0.26100)
**Usuario con permisos de administrador:** **NO** (todas las soluciones propuestas son sin admin)
**Recursos del host:** 63.5 GB RAM (29.2 GB libres) · 22 CPUs lógicas · 43.5 GB libres en `C:`

---

## 1. Tabla de herramientas

| # | Herramienta | Versión detectada | Requisito del reto | Estado |
|---|-------------|-------------------|--------------------|--------|
| 1 | **git** | `2.47.1.windows.1` | ≥ 2.30 | ✅ **OK** |
| 2 | **docker (CLI)** | `29.5.3-rd` (build 5d9ffe3) — el sufijo `-rd` confirma que es el CLI de **Rancher Desktop** | CLI funcional | ✅ **OK** |
| 3 | **docker (Server / daemon)** | `29.5.3` — `Rancher Desktop WSL Distribution`, 22 CPUs, 33.4 GB | Daemon corriendo | ✅ **OK** (tras arrancar Rancher Desktop — ver §3.1) |
| 4 | **docker compose** | `v5.1.4` | No requerido por el reto | ✅ OK (no se usará) |
| 5 | **java** | `17.0.12` (Temurin/Oracle LTS) | JDK **21** para Spring Boot 4 | ⚠️ **Alternativa aplicada** → el build multi-stage compila con JDK 21 **dentro del contenedor**. No es bloqueante. |
| 6 | **mvn** | *no instalado* | Maven **3.9+** | ⚠️ **Alternativa aplicada** → la etapa `build` del Dockerfile trae Maven 3.9.x. No es bloqueante. |
| 7 | **kubectl** | `v1.32.7` (Kustomize v5.5.0) | CLI de Kubernetes | ✅ **OK** |
| 8 | **minikube** | `v1.38.1` (commit `c93a4cb9`) | Clúster local | ✅ **OK** (instalado sin admin — ver §3.3) |
| 9 | **helm** | `v4.2.1` | No requerido | ✅ OK (no se usará) |
| 10 | **PowerShell** | `7.6.5` (pwsh) | 5.1 o 7.x | ✅ **OK** |
| 11 | **podman** | `C:\Program Files\RedHat\Podman\podman.exe` | No requerido | ℹ️ Presente. Coexiste sin conflicto (WSL `podman-machine-default` detenida). |
| 12 | **chocolatey** | `C:\ProgramData\chocolatey\bin\choco.exe` | No requerido | ⚠️ Presente pero **inutilizable sin admin** (escribe en `C:\ProgramData`). No se usará. |

---

## 2. Configuración de Rancher Desktop (leída de `settings.json`)

Archivo: `C:/Users/u30951/AppData/Local/rancher-desktop/settings.json`

| Ajuste | Valor actual | Valor requerido | Estado |
|--------|--------------|-----------------|--------|
| `containerEngine.name` | **`moby`** | `moby` (dockerd) | ✅ **CORRECTO** — el CLI `docker` funcionará. No hay que tocar nada. |
| `kubernetes.enabled` | **`true`** (v1.34.6) | **`false`** | ⛔ **DEBE DESACTIVARSE** — ver §3.2 |
| `application.adminAccess` | `false` | `false` | ✅ Coherente con la ausencia de permisos de admin |
| `WSL.integrations` | `{}` (vacío) | — | ℹ️ Sin integración a distros propias. Irrelevante: usamos el CLI de Windows. |
| `experimental.virtualMachine.proxy.enabled` | `false` | — | ✅ Coherente: no hay proxy |
| `virtualMachine.memoryInGB` / `numberCPUs` | `2` / `2` | — | ℹ️ **Se ignoran en Windows**: la VM es WSL2 y su memoria la gobierna `%USERPROFILE%\.wslconfig`. Ese archivo **no existe**, por lo que WSL2 usa el default de Windows 11 (≈50 % de la RAM ≈ 31 GB). Suficiente para `minikube --memory=4096`. **No hay que crear `.wslconfig`.** |

### Distribuciones WSL2 detectadas
```
podman-machine-default    Stopped    2
rancher-desktop-data      Stopped    2
rancher-desktop           Stopped    2
```
Las tres están **detenidas**, lo que confirma que Rancher Desktop no está en ejecución.

---

## 3. Acciones pendientes (bloqueantes) — ✅ TODAS RESUELTAS

### 3.1 ✅ Arrancar Rancher Desktop
*Estado inicial:* el daemon no respondía (`npipe:////./pipe/docker_engine` inexistente).
**Acción humana ejecutada:** abrir Rancher Desktop y esperar a "Running".
**Verificado:** `Server Version: 29.5.3` · `Rancher Desktop WSL Distribution` · 22 CPUs · 33.4 GB.

### 3.2 ✅ Desactivar Kubernetes en Rancher Desktop
*Estado inicial:* `kubernetes.enabled = true`. Si se dejaba activo:
- Rancher Desktop registra su propio contexto en `~/.kube/config` y **compite con el contexto de Minikube** → riesgo real de aplicar los manifiestos en el clúster equivocado.
- Consume ~2 GB de RAM y 2 vCPU dentro de la misma VM WSL2 donde luego correrá el contenedor de Minikube.

**Acción humana ejecutada:** *Preferences → Kubernetes → desmarcar "Enable Kubernetes" → Apply*.

### 3.3 ✅ Instalar Minikube (sin permisos de administrador)
**Verificado:** `minikube version: v1.38.1` (commit `c93a4cb9`).
Estrategia sin admin: binario descargado a `%USERPROFILE%\bin` y esa carpeta añadida
al **PATH de usuario** (`HKCU`), que no requiere elevación.

---

## 3-bis. ⚠️ RIESGO CRÍTICO DETECTADO: contexto activo de `kubectl`

Al verificar los contextos apareció esto:

```
CURRENT   NAME                               CLUSTER
*         aks-corporativo-REDACTADO          aks-corporativo-REDACTADO
          rancher-desktop                    rancher-desktop
```

El contexto **activo** de `kubectl` en este equipo es un **clúster Azure AKS
corporativo real**. Un `kubectl apply -f k8s/` sin cualificar desplegaría el
reto académico sobre infraestructura de la empresa.

**Mitigación implementada** (`scripts/00-config.ps1`):
1. La función `Assert-ContextoMinikube` se ejecuta antes de cualquier `kubectl`
   y aborta si el contexto `minikube` no existe.
2. **Todos** los comandos de Kubernetes de estos scripts llevan
   `--context minikube` de forma **explícita**, de modo que el contexto activo
   del sistema es irrelevante y nunca se toca el clúster corporativo.
3. Se define el atajo `kc` = `kubectl --context minikube`.

Detalle en `docs/DECISIONES.md` (ADR-09).

---

## 4. Red corporativa

> **⚠️ CORRECCIÓN IMPORTANTE.** La primera versión de este documento concluyó
> *«no hay inspección TLS»* a partir de una sola prueba (`registry-1.docker.io`,
> que resultó estar **exento**). Al fallar el `docker build` de la FASE 3 se
> amplió el muestreo y apareció el hallazgo real: **sí hay inspección TLS, pero
> es SELECTIVA por categoría de destino**. Se documenta el error de método
> porque es la lección técnica más valiosa del diagnóstico: *una sola muestra no
> caracteriza una política de firewall.*

### 4.1 Proxy

| Comprobación | Resultado |
|--------------|-----------|
| `$env:HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | **vacías** |
| Proxy de WinINET (`HKCU\...\Internet Settings`) | `ProxyEnable = 0`, sin `ProxyServer`, sin `AutoConfigURL` (sin PAC) |

**No hay proxy.** Los `ARG HTTP_PROXY/HTTPS_PROXY/NO_PROXY` del `Dockerfile` se
dejan por portabilidad, pero quedan vacíos e inertes. `minikube start` no
necesita los flags `--docker-env HTTP_PROXY=...`.

### 4.2 Inspección TLS — FortiGate con *deep inspection* selectiva

Emisor real del certificado presentado en cada destino (medido abriendo el
handshake TLS y leyendo el `Issuer`):

| Destino | Emisor del certificado | Veredicto |
|---------|------------------------|-----------|
| `repo.maven.apache.org` | `O=Fortinet, CN=FG7H0GTB26000121` | 🔴 **INTERCEPTADO** |
| `auth.docker.io` | `O=Fortinet, CN=FG7H0GTB26000121` | 🔴 **INTERCEPTADO** |
| `github.com` | `O=Fortinet, CN=FG7H0GTB26000121` | 🔴 **INTERCEPTADO** |
| `ghcr.io` | `O=Fortinet, CN=FG7H0GTB26000121` | 🔴 **INTERCEPTADO** |
| `registry-1.docker.io` | `O=Amazon, CN=Amazon RSA 2048 M01` | 🟢 limpio |
| `mcr.microsoft.com` | `O=Microsoft Corporation` | 🟢 limpio |
| `registry.k8s.io` | `O=Google Trust Services, CN=WR3` | 🟢 limpio |
| `gcr.io` | `O=Google Trust Services, CN=WE2` | 🟢 limpio |
| `storage.googleapis.com` | `O=Google Trust Services, CN=WR2` | 🟢 limpio |
| `objects.githubusercontent.com` | `O=Let's Encrypt, CN=YR1` | 🟢 limpio |

El patrón es coherente con una política habitual: el FortiGate **excluye de la
inspección los registros de contenedores y los CDN de binarios** (romperlos
genera muchas incidencias) pero **sí inspecciona** las categorías web generales,
donde caen Maven Central y GitHub.

En el almacén `LocalMachine\Root` de Windows hay **22 CA raíz de Fortinet**
instaladas por TI. La que firma el tráfico actual es
`CN=FG7H0GTB26000121` (huella `FEC0…CACD`, válida hasta 2036-07-01).

### 4.3 Por qué esto rompió el build (y por qué `docker pull` sí funcionaba)

| Componente | ¿Confía en la CA de Fortinet? | Consecuencia |
|------------|------------------------------|--------------|
| Windows (.NET, navegador) | ✅ Sí — TI la instaló en `LocalMachine\Root` | Todo funciona en el host |
| Distro WSL2 de Rancher Desktop | ✅ Sí — Rancher propaga las CA raíz de Windows | `docker pull` / `docker login` / `docker push` funcionan |
| **Contenedor de la etapa `build`** | ❌ **No** — trae su propio `cacerts` de la JVM | **Maven falla** |

Error exacto obtenido en la FASE 3:

```
[FATAL] Non-resolvable parent POM ... spring-boot-starter-parent:pom:4.1.0
Could not transfer artifact ... from/to central (https://repo.maven.apache.org/maven2):
(certificate_unknown) PKIX path building failed:
sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
```

> **Nota de método:** el síntoma (`spring-boot-starter-parent:4.1.0` no resuelve)
> es exactamente el que el enunciado del reto anticipaba como *«posible Nexus
> corporativo sin sincronizar»*. **No era esa la causa.** La versión 4.1.0 existe
> y es alcanzable; lo que fallaba era la validación del certificado. Confirmarlo
> antes de bajar a Spring Boot 3.5.x evitó una degradación innecesaria del
> proyecto. **No se cambió ninguna versión del `pom.xml`.**

### 4.4 Solución aplicada

`scripts/00-extraer-ca-corporativa.ps1` exporta las CA del almacén de Windows
(sin permisos de administrador, solo lectura) a `certs/*.crt`, y el `Dockerfile`
las importa en la etapa `build` tanto en el truststore del SO
(`update-ca-certificates`) como en el de la JVM (`keytool -importcert -cacerts`).

`certs/*.crt` está en `.gitignore`: **no se publica en el fork**, porque revela
el número de serie del equipamiento de seguridad de la empresa. La carpeta lleva
un `.gitkeep` para que el `COPY certs/ /opt/corp-ca/` funcione siempre, y el
bloque `RUN` detecta si está vacía — el build sigue siendo portable fuera de la
red corporativa. Detalle completo en `docs/DECISIONES.md` (ADR-08).

### 4.5 Impacto en las fases siguientes

| Fase | Impacto |
|------|---------|
| FASE 3 — build | ✅ Resuelto con la inyección de CA. Build verificado OK. |
| FASE 4 — Docker Hub | 🟢 Sin impacto: `registry-1.docker.io` está exento y la distro WSL confía en la CA para `auth.docker.io`. |
| FASE 6 — Minikube | 🟢 Sin impacto: `registry.k8s.io`, `gcr.io` y `storage.googleapis.com` están exentos. |
| Plan B `ghcr.io` | 🟡 Está interceptado; funcionaría igual porque el daemon confía en la CA, pero se prefiere Docker Hub. |

**Riesgo residual:** el *rate limit* anónimo de Docker Hub (100 pulls / 6 h por
IP NAT corporativa). Se mitiga usando `mcr.microsoft.com` para la imagen de
runtime y haciendo `docker login` antes del build.

## 5. Riesgo detectado fuera de la tabla: carpeta de trabajo en OneDrive

El directorio actual es:
`C:/Users/<usuario>/OneDrive - <empresa>/Desktop/Diplomado de Arquitectura/Reto 5`

Está **sincronizado por OneDrive**. Clonar ahí el repositorio y ejecutar `docker build` provoca dos problemas conocidos:
1. OneDrive bloquea archivos de `.git/` y de `target/` mientras los sincroniza → `git` y Maven fallan de forma intermitente.
2. El contexto de build (`docker build .`) puede incluir archivos *cloud-only* (placeholders de 0 bytes) y romper la compilación.

**Decisión aplicada (FASE 1):** el fork se clonó en **`C:/dev/micro-calc`**, fuera de OneDrive. En la carpeta de OneDrive quedan únicamente el PDF y las capturas finales.

---

## 6. Resumen ejecutivo

| Categoría | Veredicto |
|-----------|-----------|
| Herramientas listas | git 2.47.1 · docker CLI 29.5.3-rd · docker Server 29.5.3 · kubectl v1.32.7 · minikube v1.38.1 · PowerShell 7.6.5 |
| No bloqueantes (resueltos por el multi-stage) | java 17 en el host en vez de 21 · Maven ausente → ambos los aporta la etapa `build` del contenedor |
| Bloqueantes iniciales | ✅ Los 3 resueltos (daemon detenido · K8s de Rancher activo · Minikube ausente) |
| **Hallazgo mayor** | **FortiGate con inspección TLS SELECTIVA.** Rompía el `mvn` dentro del contenedor con `PKIX path building failed`. Resuelto inyectando la CA corporativa en la etapa `build`. **No hizo falta degradar Spring Boot 4.1.0.** |
| **Riesgo mayor** | Contexto activo de `kubectl` = clúster **AKS corporativo**. Mitigado con `--context minikube` explícito en todos los scripts. |
| Proxy | Ninguno (ni variables de entorno, ni WinINET, ni PAC) |
| Permisos de administrador | **No disponibles.** Ninguna solución aplicada los requiere. |
| Hardware | Sobrado: 63.5 GB RAM · 22 vCPU · 43.5 GB libres en `C:` |
| Herramientas de pago | **Ninguna.** Rancher Desktop, Minikube, Docker Hub free, MCR y Maven Central son gratuitos. |

---

## 7. Resultado de la FASE 3 (build verificado)

| Métrica | Valor medido |
|---------|--------------|
| Build completo (sin caché) | 167.8 s |
| Tests | `Tests run: 1, Failures: 0, Errors: 0, Skipped: 0` → **BUILD SUCCESS** |
| Tamaño real de la imagen (`docker image inspect .Size`) | **220.6 MB** (231 350 463 bytes) |
| Capas en la imagen final | 6 (solo runtime; Maven y `~/.m2` se quedan en la etapa `build`) |
| Usuario del proceso | `uid=10001(spring) gid=10001(spring)` — **no root** |
| PID 1 | `java -XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError -jar /app/app.jar` |
| `MaxRAMPercentage` con `--memory=512m` | `MaxHeapSize = 402 653 184` = **384 MiB = 75 % de 512 MiB** ✅ |
| Java del runtime | 21.0.12.1 · Spring Boot 4.1.0 · Tomcat 11.0.22 |

> ⚠️ La columna `SIZE` de `docker images` mostraba **733 MB**. No es el tamaño de
> la imagen: Docker 29 usa el almacén de imágenes de **containerd** (snapshotter
> `overlayfs`) y esa columna agrega todos los blobs del *content store*
> asociados al nombre. El dato correcto para saber qué se va a publicar es
> `docker image inspect --format '{{.Size}}'`.
