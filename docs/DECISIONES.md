# Decisiones de arquitectura (ADR)

Registro de decisiones tomadas durante el Reto 5 del Diplomado de Arquitectura
de Software. Cada entrada sigue el formato **contexto → opciones evaluadas →
decisión → consecuencias**.

> Todas las cifras de este documento son **medidas reales** en el equipo de
> trabajo el **2026-08-21**, no estimaciones.

**Índice**

| ADR | Título | Estado |
|-----|--------|--------|
| [ADR-01](#adr-01--build-multi-stage-frente-a-build-local) | Build multi-stage frente a build local | Aceptada |
| [ADR-02](#adr-02--elección-de-la-imagen-base-de-runtime) | Elección de la imagen base de runtime | Aceptada |
| [ADR-03](#adr-03--registro-de-imágenes-docker-hub-ghcrio-o-mcr) | Registro de imágenes: Docker Hub, ghcr.io o MCR | Aceptada |
| [ADR-04](#adr-04--tag-inmutable-frente-a-latest-en-el-deployment) | Tag inmutable frente a `:latest` en el Deployment | Aceptada |
| [ADR-05](#adr-05--configmap-frente-a-valores-empotrados-en-la-imagen) | ConfigMap frente a valores empotrados en la imagen | Aceptada |
| [ADR-06](#adr-06--nodeport-frente-a-port-forward-para-la-validación) | NodePort frente a port-forward para la validación | Aceptada |
| [ADR-07](#adr-07--driverdocker-frente-a-driverhyperv-en-minikube) | `--driver=docker` frente a `--driver=hyperv` | Aceptada |
| [ADR-08](#adr-08--probes-contra--frente-a-spring-boot-actuator) | Probes contra `/` frente a Spring Boot Actuator | Aceptada |
| [ADR-09](#adr-09--inyección-de-la-ca-corporativa-de-inspección-tls) | Inyección de la CA corporativa de inspección TLS | Aceptada |
| [ADR-10](#adr-10--contexto-de-kubectl-explícito-en-todos-los-scripts) | Contexto de `kubectl` explícito en todos los scripts | Aceptada |
| [ADR-11](#adr-11--conservar-spring-boot-410-y-no-degradar-a-35x) | Conservar Spring Boot 4.1.0 y no degradar a 3.5.x | Aceptada |
| [ADR-12](#adr-12--script-compartido-00-configps1-fuera-de-la-estructura-pedida) | Script compartido `00-config.ps1` fuera de la estructura pedida | Aceptada |

---

## ADR-01 · Build multi-stage frente a build local

### Contexto
El proyecto exige **JDK 21** (`java.version=21` en el `pom.xml`) y **Maven 3.9+**
(lo impone `spring-boot-starter-parent:4.1.0`). El equipo de trabajo tiene:

- `java 17.0.12` — **versión insuficiente**
- `mvn` — **no instalado**
- El `mvnw` del repositorio apunta a **Maven 3.8.6** — **insuficiente**
- **Sin permisos de administrador** para instalar un JDK 21 en `Program Files`

### Opciones evaluadas

| Opción | Valoración |
|--------|-----------|
| Instalar JDK 21 + Maven 3.9 en el host | Requiere admin, o una instalación portable manual. Acopla el build a la máquina y no es reproducible por otro compañero. |
| Actualizar `maven-wrapper.properties` a 3.9.9 y usar `./mvnw` | Resuelve Maven, pero **no** el JDK 17. Además modifica el repositorio original. |
| **Build multi-stage dentro del contenedor** | El contenedor aporta JDK 21 y Maven 3.9. El host solo necesita Docker. |

### Decisión
**Build multi-stage.** La etapa `build` usa `maven:3.9-eclipse-temurin-21`; la
etapa `runtime` recibe únicamente el JAR compilado.

No se toca `.mvn/wrapper/maven-wrapper.properties`: el wrapper se excluye del
contexto de build en el `.dockerignore` y **no se usa en absoluto**.

### Consecuencias

**Positivas**
- El build es reproducible en cualquier máquina con Docker, sin Java ni Maven.
- La imagen final **no contiene** Maven, ni el código fuente, ni el repositorio
  `~/.m2`. Menos superficie de ataque.
- Con `COPY pom.xml` + `mvn dependency:go-offline` antes de `COPY src`, las
  dependencias quedan en una capa cacheada: un rebuild tras cambiar código tarda
  segundos.

**Negativas**
- El primer build es lento: **167,8 s medidos**. Los siguientes, con caché, son
  de segundos.
- El desarrollador no puede compilar fuera de Docker sin instalarse JDK 21.

**Verificación**
```
Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
```
Los tests se ejecutan **dentro del build** a propósito: `contextLoads()` valida
que el contexto de Spring levanta con las propiedades empaquetadas.

---

## ADR-02 · Elección de la imagen base de runtime

### Contexto
La etapa de runtime solo necesita ejecutar un JAR. Se busca la imagen más
pequeña y con menos superficie posible, pero también un registro fiable.

### Opciones evaluadas (tamaños medidos)

| Imagen | Tipo | Tamaño base | Imagen final | Registro |
|--------|------|-------------|--------------|----------|
| `mcr.microsoft.com/openjdk/jdk:21-ubuntu` | JDK | 213 MB | **220,6 MB** | MCR (sin *rate limit*) |
| `eclipse-temurin:21-jre-jammy` | JRE | 99 MB | ~117 MB | Docker Hub (con *rate limit*) |
| `mcr.microsoft.com/openjdk/jdk:21-distroless` | JDK sin shell | menor | menor | MCR |

### Decisión
**`mcr.microsoft.com/openjdk/jdk:21-ubuntu`**, parametrizada como
`ARG RUNTIME_IMAGE` para poder cambiarla sin editar el `Dockerfile`:

```powershell
docker build --build-arg RUNTIME_IMAGE=eclipse-temurin:21-jre-jammy .
```

### Consecuencias

**Positivas**
- MCR **no aplica el *rate limit* anónimo de Docker Hub** (100 *pulls* / 6 h por
  IP), un riesgo real detrás de una IP NAT corporativa compartida.
- Verificado: `mcr.microsoft.com` **no está interceptado** por el FortiGate
  (emisor real `Microsoft TLS G2 RSA CA`), a diferencia de `auth.docker.io`.
- Base Ubuntu con `groupadd`/`useradd`, necesarios para crear el usuario 10001.

**Negativas**
- MCR **solo publica JDK, no JRE**: la imagen pesa **~104 MB más** que con
  `eclipse-temurin:21-jre-jammy`. Es el precio explícito de la decisión.
- Un JDK incluye compilador y herramientas que la aplicación no necesita, lo que
  amplía ligeramente la superficie de ataque.

**Descartada:** `21-distroless` sería más pequeña y más segura, pero **no tiene
shell**, así que no permite `useradd` ni `update-ca-certificates`, y este último
es imprescindible en la etapa `build` por la inspección TLS (ver [ADR-09](#adr-09--inyección-de-la-ca-corporativa-de-inspección-tls)).
Para la etapa de *runtime* sí sería viable y queda como mejora futura.

---

## ADR-03 · Registro de imágenes: Docker Hub, ghcr.io o MCR

### Contexto
Hay que publicar la imagen en un registro público desde el que Minikube pueda
descargarla. El entorno es corporativo, con firewall e inspección TLS.

### Opciones evaluadas

| Registro | Coste | Estado en esta red | Valoración |
|----------|-------|--------------------|-----------|
| **Docker Hub** | Gratis (repos públicos ilimitados) | `registry-1.docker.io` **no interceptado**; `auth.docker.io` **sí** | Es lo que pide el reto. |
| `ghcr.io` | Gratis para paquetes públicos | **Interceptado** por el FortiGate | Funcionaría, pero no aporta nada aquí. |
| MCR | Solo lectura | No interceptado | **No admite publicación**: es un registro de Microsoft. |

### Decisión
**Docker Hub**, con `ghcr.io` implementado como plan B accionable:

```powershell
.\scripts\02-push-dockerhub.ps1 -Registro ghcr
```

Autenticación con **Personal Access Token**, nunca con contraseña: los entornos
corporativos con SSO suelen rechazar la contraseña en el CLI, y el token es
revocable de forma independiente.

### Consecuencias

**Positivas**
- Imagen pública verificada: `is_private: false`, 3 tags, **220,6 MB**.
- La verificación no se limita a *«el push no dio error»*: el script borra la
  imagen del disco y la vuelve a descargar, comprobando que el identificador
  coincide. Esto descarta que estuviéramos viendo una caché local.
- Digest publicado: `sha256:3aecbb12d624817e375456aa8a6ac47ac30de3104f255366d89ad2c297e65173`

**Negativas**
- Docker Hub limita a **1 repositorio privado** en el plan gratuito; aquí no
  importa porque el repositorio debe ser público para que Minikube haga *pull*
  sin `imagePullSecret`.
- El *rate limit* de *pulls* anónimos sigue siendo un riesgo si muchos equipos
  comparten la IP de salida.

**Hallazgo operativo:** `docker info --format '{{.Username}}'` devuelve **vacío**
aunque la sesión esté activa, porque Rancher Desktop usa
`"credsStore": "wincred"` y el token vive en el Administrador de credenciales de
Windows, no en `config.json`. La detección de sesión del script tuvo que
reescribirse para no abortar por eso.

---

## ADR-04 · Tag inmutable frente a `:latest` en el Deployment

### Contexto
Se publican tres tags que apuntan al mismo digest: `:1.0.0`, `:latest` y
`:ffd72bc` (SHA corto del commit). Hay que decidir cuál referencia el Deployment.

### Opciones evaluadas

| Tag | Problema |
|-----|----------|
| `:latest` | Es un **puntero móvil**. No se puede saber qué versión corre en el clúster. El rollback no es reproducible. Dos Pods creados con minutos de diferencia pueden ejecutar código distinto. Combinado con `imagePullPolicy: IfNotPresent`, unos nodos tendrían una versión cacheada y otros otra. |
| `:1.0.0` | Versión semántica, legible, estable. |
| `:ffd72bc` | Máxima trazabilidad al commit, pero ilegible en `kubectl get pods`. |
| `@sha256:...` | Inmutabilidad criptográfica total, pero ilegible y engorroso de actualizar. |

### Decisión
**`gthen95/micro-calc:1.0.0`** en el Deployment. El tag `:latest` existe solo
para pruebas manuales (`docker run`), y `:ffd72bc` para trazabilidad.

### Consecuencias

**Positivas**
- `kubectl describe pod` dice exactamente qué versión corre.
- El rollback es determinista.
- `imagePullPolicy: IfNotPresent` es seguro: con un tag inmutable, la copia
  cacheada del nodo **es** la imagen correcta por definición.

**Negativas**
- Publicar una versión nueva obliga a editar el `Deployment` (o usar Kustomize /
  Helm). Es un coste deseable: hace el cambio explícito y auditable.

**Verificado en el clúster** — el `imageID` que reporta el nodo incluye el digest
de Docker Hub, lo que prueba que la imagen se descargó del registro:
```
docker-pullable://gthen95/micro-calc@sha256:3aecbb12d624817e375456aa8a6ac47ac30de3104f255366d89ad2c297e65173
```

---

## ADR-05 · ConfigMap frente a valores empotrados en la imagen

### Contexto
`ControlCalculadora.java` inyecta tres propiedades con `@Value` **sin valor por
defecto**:

```java
@Value("${app.message.error}") private String mensajeError;
@Value("${db.server}")         private String server;
@Value("${db.user}")           private String user;
```

Si alguna falta, Spring no construye el bean y el contexto **no arranca**: el
Pod entra en `CrashLoopBackOff`. La imagen lleva `application.properties`
empaquetado, así que hay valores de respaldo, pero dejarlos ahí significaría que
cambiar de entorno exige **reconstruir y republicar la imagen**.

### Opciones evaluadas

| Opción | Valoración |
|--------|-----------|
| Valores en `application.properties` dentro del JAR | Una imagen distinta por entorno. Rompe el principio *build once, deploy anywhere*. |
| `env:` con valores literales en el Deployment | Funciona, pero mezcla configuración con la definición de la carga de trabajo y no se reutiliza. |
| **ConfigMap + `envFrom`** | La configuración es un objeto propio, versionable y reutilizable. Una sola clave `envFrom` inyecta todas las variables. |
| Secret | Innecesario: nada de esto es sensible. Un Secret solo está codificado en base64, no cifrado; usarlo aquí daría una falsa sensación de seguridad. |

### Decisión
**ConfigMap `micro-calc-config` + `envFrom`**, apoyado en el *relaxed binding* de
Spring Boot:

| Propiedad | Variable de entorno |
|-----------|--------------------|
| `app.message.error` | `APP_MESSAGE_ERROR` |
| `db.server` | `DB_SERVER` |
| `db.user` | `DB_USER` |

Las variables de entorno tienen **más prioridad** que `application.properties` en
el orden de precedencia de Spring Boot, así que los valores del ConfigMap ganan.

Los valores son **deliberadamente distintos en cada entorno** para que la
evidencia sea inequívoca:

| Origen | `db.user` | `db.server` |
|--------|-----------|-------------|
| `application.properties` (dentro del JAR) | `admin` | `localhost` |
| `docker run -e ...` (FASE 3) | `gerald` | `docker-local` |
| **ConfigMap** (FASE 7) | **`gerald-k8s`** | **`k8s-minikube`** |

### Consecuencias

**Positivas**
- La **misma imagen** sirve para local, Docker y Kubernetes.
- Ver `gerald-k8s,k8s-minikube` en el navegador demuestra sin ambigüedad de
  dónde sale la configuración. Es la evidencia central del reto.

**Negativas**
- `envFrom` **no recarga en caliente**: las variables se fijan al crear el
  contenedor. Cambiar el ConfigMap exige
  `kubectl rollout restart deployment/micro-calc -n micro-calc`. Se documenta
  con la anotación `reto5.diplomado/config-source` en el `podTemplate`.
- El ConfigMap se convierte en una dependencia dura: si se borra, los Pods
  nuevos arrancan con los valores del JAR (no fallarían, pero servirían datos
  incorrectos de forma silenciosa).

**Verificado:**
```
GET /          -> gerald-k8s,k8s-minikube
GET /div/10/0  -> {"error":"Division por cero no permitida (valor desde ConfigMap)"}
```

---

## ADR-06 · NodePort frente a port-forward para la validación

### Contexto
Hay que alcanzar la aplicación desde el navegador de **Windows**. El clúster es
Minikube con `--driver=docker`.

### El problema de red, en concreto
El «nodo» de Kubernetes es un **contenedor** que corre dentro de la **VM WSL2**
de Rancher Desktop. Su IP (`192.168.49.2`) pertenece a una red *bridge* de Docker
**interna a esa VM**. El host Windows **no tiene ruta** hacia ella, así que
`http://192.168.49.2:30080` normalmente da *timeout* desde el navegador aunque el
Service esté perfectamente configurado.

```
Windows  ──X──>  192.168.49.2:30080      (sin ruta)
Windows  ─────>  127.0.0.1:8081  ──tunel──> API server ──> Pod:8080   (funciona)
```

### Opciones evaluadas

| Método | Fiabilidad en Windows | Notas |
|--------|----------------------|-------|
| **`kubectl port-forward`** | **Alta** | Túnel sobre la conexión HTTPS que kubectl ya tiene con el API server. No depende de la topología de red. |
| `minikube service --url` | Media | Minikube abre su propio túnel. **En esta prueba sí funcionó**: devolvió `http://127.0.0.1:51164` y respondió `42`. Requiere mantener el proceso vivo y el puerto es aleatorio. |
| NodePort directo a `minikube ip` | Baja | Falla por lo explicado arriba. |
| `LoadBalancer` | No aplica | Sin proveedor en Minikube; quedaría en `<pending>` salvo `minikube tunnel`. |
| `Ingress` | Excesivo | Otra capa de indirección para un único servicio. |

### Decisión
Se **declara un Service NodePort** (`30080`), porque es lo que pide el reto y es
la forma canónica de exponer un servicio en un clúster sin *cloud provider*, pero
**la validación se hace con `port-forward`**, y el script prueba los tres métodos
en orden de fiabilidad.

### Consecuencias

**Positivas**
- El manifiesto es correcto y portable: en un clúster real con acceso a la red
  de nodos, el NodePort funcionaría tal cual.
- Los tres métodos documentados enseñan *por qué* falla cada uno, en vez de
  ocultarlo.

**Negativas / limitación descubierta en la práctica**
- **`kubectl port-forward svc/<nombre>` NO balancea.** Resuelve el Service una
  sola vez, elige **un Pod concreto** y mantiene el túnel contra ese Pod. Durante
  la prueba de resiliencia, al borrar precisamente ese Pod, **el túnel murió**
  aunque el Service seguía sirviendo desde la otra réplica. Es una limitación de
  la herramienta de depuración, no un fallo de la aplicación. El script se
  modificó para reabrir el túnel y demostrarlo explícitamente.

---

## ADR-07 · `--driver=docker` frente a `--driver=hyperv` en Minikube

### Contexto
Windows 11 Enterprise, **sin permisos de administrador**, con Rancher Desktop ya
en marcha sobre WSL2.

### Opciones evaluadas

| Driver | Requiere admin | Consumo | Valoración |
|--------|---------------|---------|-----------|
| **`docker`** | **No** | Reutiliza la VM WSL2 existente | El nodo es un contenedor más en el daemon que ya está corriendo. |
| `hyperv` | **Sí** — pertenecer a *Hyper-V Administrators* | VM completa adicional | Descartado: no hay permisos, y duplicaría el consumo de RAM al levantar una segunda VM junto a la de WSL2. |
| `virtualbox` | Sí (instalación) | VM completa | Descartado: incompatible con Hyper-V/WSL2 activos. |
| `none` / `ssh` | — | — | No aplica en Windows. |

### Decisión
**`--driver=docker`**, con `--cpus=2 --memory=4096`.

### Consecuencias

**Positivas**
- Cero elevación de privilegios, cero VM adicional.
- Arranque medido: **117,3 s** (incluye descargar la imagen base `kicbase` de
  519 MB la primera vez).
- Comparte el daemon con Rancher Desktop, lo que habilita el plan B
  `minikube image load`.

**Negativas**
- Es la causa raíz del problema de red del [ADR-06](#adr-06--nodeport-frente-a-port-forward-para-la-validación).
- El nodo hereda la red de la VM WSL2, y con ella los problemas de esa red — en
  particular la inspección TLS del [ADR-09](#adr-09--inyección-de-la-ca-corporativa-de-inspección-tls).
- `minikube` avisa de que **a partir de v1.39.0 el runtime por defecto pasará a
  `containerd`**. Cuando ocurra, `minikube image load` seguirá funcionando pero
  `minikube ssh -- docker ...` no.

**Nota sobre memoria:** los ajustes `virtualMachine.memoryInGB` y `numberCPUs` de
`settings.json` de Rancher Desktop **se ignoran en Windows**: la VM es WSL2 y su
memoria la gobierna `%USERPROFILE%\.wslconfig`. Ese archivo no existe, así que
WSL2 usa el reparto por defecto de Windows 11 (≈50 % de 63,5 GB ≈ 31 GB), de
sobra para los 4096 MB de Minikube. **No hizo falta crear `.wslconfig`.**

---

## ADR-08 · Probes contra `/` frente a Spring Boot Actuator

### Contexto
El repositorio base **no incluye** `spring-boot-starter-actuator`, así que no
existen `/actuator/health/liveness` ni `/actuator/health/readiness`.

### Opciones evaluadas

| Opción | Valoración |
|--------|-----------|
| **Probes contra `GET /`** | Cero cambios en el código. El endpoint devuelve `usuario,servidor` con HTTP 200. |
| Añadir Actuator al `pom.xml` | Semánticamente correcto (separa *liveness* de *readiness*), pero **modifica el proyecto base** que el reto entrega. |
| `tcpSocket` sobre el 8080 | Peor: solo comprueba que el puerto escucha, no que Spring haya terminado de levantar. |
| `exec` con `curl` | La imagen base no trae `curl` ni `wget`. |

### Decisión
**Probes HTTP GET contra `/`**, sin tocar el `pom.xml`.

Hay un argumento a favor más allá de la comodidad: `/` devuelve los valores
inyectados con `@Value`. Si la configuración faltara, el contexto de Spring no
arrancaría y el endpoint no respondería. **Para esta aplicación concreta, `/` sí
es un indicador real de salud**, no un simple *ping*.

### Diseño de los tres probes

```yaml
startupProbe:   periodSeconds: 5,  failureThreshold: 30   # presupuesto 150 s
readinessProbe: periodSeconds: 10, failureThreshold: 3
livenessProbe:  periodSeconds: 20, failureThreshold: 3
```

**El `startupProbe` es el que evita el error clásico.** Sin él, el
`livenessProbe` empieza a contar desde el segundo cero, falla tres veces mientras
la JVM y Spring todavía arrancan y **mata el Pod** antes de que llegue a estar
listo → `CrashLoopBackOff` permanente. Mientras el `startupProbe` no pasa,
*liveness* y *readiness* quedan **suspendidos**.

Arranque medido de la aplicación: **~3,8 s**. El presupuesto de 150 s da un
margen holgadísimo.

El `livenessProbe` es deliberadamente **menos agresivo** que el de *readiness*:
un *liveness* nervioso provoca reinicios en cascada bajo carga, que es peor que
el problema que pretende resolver. *Readiness* solo saca el Pod del balanceo;
*liveness* lo mata.

### Consecuencias

**Positivas**
- Cero modificaciones al proyecto base.
- Verificado en `kubectl describe pod`: los tres probes en verde, sin reinicios.

**Negativas**
- No se distingue *«vivo pero no listo»* de *«vivo y listo»*: ambos probes miran
  el mismo endpoint. Con Actuator, `/health/readiness` podría reportar «no listo»
  mientras se calienta una caché o se establece una conexión a base de datos,
  algo que aquí no es posible.
- `/` no comprueba dependencias externas. En esta aplicación no las hay, pero
  no escalaría a un servicio con base de datos real.

**Recomendación si el proyecto creciera:** añadir Actuator, exponer solo
`health` y `info`, y separar los grupos *liveness* y *readiness*.

---

## ADR-09 · Inyección de la CA corporativa de inspección TLS

### Contexto
La red corporativa usa un **FortiGate con *deep inspection* SSL selectiva**.
Emisor real medido en cada destino:

| Destino | Emisor | Estado |
|---------|--------|--------|
| `repo.maven.apache.org` | `O=Fortinet, CN=FG7H0GTB26000121` | 🔴 interceptado |
| `auth.docker.io` | `O=Fortinet, CN=FG7H0GTB26000121` | 🔴 interceptado |
| `github.com`, `ghcr.io` | `O=Fortinet, CN=FG7H0GTB26000121` | 🔴 interceptado |
| `registry-1.docker.io` | `O=Amazon` | 🟢 limpio |
| `mcr.microsoft.com` | `O=Microsoft Corporation` | 🟢 limpio |
| `registry.k8s.io`, `gcr.io` | `O=Google Trust Services` | 🟢 limpio |

Windows y la distro WSL2 de Rancher Desktop **sí** confían en esa CA (TI la
instaló en `LocalMachine\Root`; hay 22 CA de Fortinet). Pero **cada contenedor
trae su propio almacén de certificados**, y ahí la CA no está. El fallo apareció
**dos veces, con la misma causa raíz**:

1. **Etapa `build` del Dockerfile** — el `cacerts` de la JVM no tiene la CA:
   ```
   [FATAL] Non-resolvable parent POM ... spring-boot-starter-parent:pom:4.1.0
   (certificate_unknown) PKIX path building failed:
   unable to find valid certification path to requested target
   ```

2. **Nodo de Minikube** — es un contenedor Debian nuevo:
   ```
   Failed to pull image "gthen95/micro-calc:1.0.0":
   Get "https://auth.docker.io/token?...": tls: failed to verify certificate:
   x509: certificate signed by unknown authority
   -> Pods en ImagePullBackOff
   ```

### Opciones evaluadas

| Opción | Valoración |
|--------|-----------|
| `-Dmaven.wagon.http.ssl.insecure=true` | **Desactiva la validación de certificados.** Enseña a ignorar errores de TLS, que es exactamente el hábito que no se quiere fomentar. Además solo aplica al transporte *wagon*, no al resolver nativo de Maven 3.9. Descartada. |
| Publicar la CA en el fork de GitHub | Simplifica el `COPY`, pero expone el número de serie del equipamiento de seguridad de la empresa en un repositorio **público**. Descartada. |
| Usar un registro *mirror* no interceptado | No resuelve Maven Central, que es el destino que falla. |
| **Inyectar la CA en los contenedores que la necesitan** | Correcto: se mantiene la validación de certificados y se añade explícitamente la CA legítima de la organización. |
| Evitar el problema con `minikube image load` | Funciona, pero **elude** la verificación de que la imagen viene de Docker Hub, que es un entregable del reto. Se conserva solo como plan B. |

### Decisión
**Inyectar la CA, sin publicarla.**

1. `scripts/00-extraer-ca-corporativa.ps1` exporta las CA del almacén de Windows
   a `certs/*.crt` (solo lectura, **sin permisos de administrador**).
2. `certs/*.crt` está en `.gitignore`. La carpeta lleva un `.gitkeep` para que
   el `COPY certs/ /opt/corp-ca/` del Dockerfile funcione siempre.
3. La etapa `build` importa las CA en el almacén del SO
   (`update-ca-certificates`) **y** en el de la JVM (`keytool -importcert -cacerts`).
4. `scripts/03-minikube-up.ps1` copia las CA a `%USERPROFILE%\.minikube\certs`
   **antes** de `minikube start` (Minikube las instala en el nodo al crearlo) y
   además las instala en caliente en un clúster ya existente.

El `Dockerfile` detecta si `certs/` está vacía y, en ese caso, no hace nada:
**el build sigue siendo portable fuera de la red corporativa.**

### Consecuencias

**Positivas**
- La validación de certificados **sigue activa**. No se desactiva TLS en ningún
  punto.
- El repositorio público no filtra información de la infraestructura de
  seguridad de la empresa.
- Reproducible: cualquiera dentro de la misma red ejecuta un script y funciona;
  fuera de ella, funciona sin ejecutarlo.
- Verificado: `docker pull` desde dentro del nodo devuelve el digest correcto y
  los Pods pasan a `Running`.

**Negativas**
- Un paso previo más que documentar.
- Las CA caducan (la activa vence el **2036-07-01**) y podrían rotar; habría que
  volver a ejecutar el script de extracción.
- Se importan las 22 CA de Fortinet en lugar de solo la activa, por robustez
  frente a cambios de *appliance*. Cuesta 31 KB.

**Nota de método** — el síntoma de (1) era **idéntico** al que el enunciado del
reto anticipaba como *«posible Nexus corporativo sin sincronizar»*, con el plan B
de degradar a Spring Boot 3.5.x. Comprobar la causa real antes de actuar evitó
una degradación innecesaria. Ver [ADR-11](#adr-11--conservar-spring-boot-410-y-no-degradar-a-35x).

---

## ADR-10 · Contexto de `kubectl` explícito en todos los scripts

### Contexto
Al inventariar el entorno apareció esto:

```
CURRENT   NAME                               CLUSTER
*         aks-corporativo-REDACTADO          aks-corporativo-REDACTADO
          rancher-desktop                    rancher-desktop
          minikube                           minikube
```

El contexto **activo** era un **clúster Azure AKS corporativo real**. Un
`kubectl apply -f k8s/` sin cualificar habría desplegado el reto académico sobre
infraestructura de la empresa.

### Opciones evaluadas

| Opción | Valoración |
|--------|-----------|
| Confiar en `kubectl config use-context minikube` al principio | Frágil: cualquier otra terminal, script o herramienta puede cambiarlo entre pasos. Un fallo silencioso con consecuencias graves. |
| `KUBECONFIG` apuntando a un archivo aislado | Robusto, pero rompe `minikube` y obliga a gestionar un archivo aparte. |
| **`--context minikube` explícito en cada comando + guard previo** | Cada comando declara su destino. El contexto activo del sistema pasa a ser irrelevante. |

### Decisión
**Las dos cosas:**

1. `Assert-ContextoMinikube` (en `scripts/00-config.ps1`) se ejecuta antes de
   cualquier `kubectl` y aborta si el contexto `minikube` no existe. Si el
   contexto activo es otro, avisa por pantalla en rojo.
2. **Todos** los comandos de Kubernetes llevan `--context minikube` explícito.
   Se define además el atajo `kc` = `kubectl --context minikube`.

### Consecuencias

**Positivas**
- Es **imposible** que estos scripts toquen el clúster corporativo, sea cual sea
  el contexto activo.
- La intención queda documentada en el propio código.

**Negativas**
- Los comandos son más largos y hay que recordar la regla al añadir uno nuevo.
- Los comandos que el usuario copie a mano fuera de los scripts no llevan la
  protección; por eso todos los ejemplos de la documentación la incluyen.

---

## ADR-11 · Conservar Spring Boot 4.1.0 y no degradar a 3.5.x

### Contexto
El enunciado del reto preveía que `spring-boot-starter-parent:4.1.0` pudiera no
resolver si un Nexus/Artifactory corporativo no lo tuviera sincronizado, y
proponía como plan B bajar a la última 3.5.x documentando el cambio.

El error apareció **exactamente con ese síntoma**:

```
[FATAL] Non-resolvable parent POM for com.mauricio:demo-micro:0.0.1-SNAPSHOT:
The following artifacts could not be resolved:
org.springframework.boot:spring-boot-starter-parent:pom:4.1.0 (absent)
```

### Investigación
Antes de degradar nada se leyó el mensaje **completo**, no solo la primera línea:

```
Could not transfer artifact ... from/to central (https://repo.maven.apache.org/maven2):
(certificate_unknown) PKIX path building failed
```

Comprobaciones realizadas:

1. `repo.maven.apache.org` responde **HTTP 200** desde Windows → **no hay Nexus
   intermedio**, Maven Central se alcanza directamente.
2. El emisor del certificado es `O=Fortinet` → **el fallo es de validación TLS,
   no de disponibilidad del artefacto**.
3. La versión 4.1.0 existe y es descargable.

### Decisión
**No degradar.** Se mantiene `spring-boot-starter-parent:4.1.0` y
`java.version=21` **sin ninguna modificación del `pom.xml`**. Se corrige la causa
real: la confianza en la CA ([ADR-09](#adr-09--inyección-de-la-ca-corporativa-de-inspección-tls)).

### Consecuencias

**Positivas**
- El proyecto entregado es **idéntico** al del repositorio base en cuanto a
  dependencias. Cero deuda técnica introducida.
- Build verificado: `BUILD SUCCESS`, Spring Boot 4.1.0, Java 21.0.12.1,
  Tomcat 11.0.22.

**Negativas**
- Requirió diagnosticar la red en vez de aplicar el plan B, que habría sido más
  rápido.

**Lección** — *«el artefacto no se pudo resolver»* y *«el artefacto no existe»*
son cosas distintas. Un mensaje de Maven suele traer la causa real varias líneas
más abajo, y actuar sobre la primera línea lleva a arreglar el problema
equivocado.

---

## ADR-12 · Script compartido `00-config.ps1` fuera de la estructura pedida

### Contexto
La estructura solicitada enumera seis scripts (`01`…`05`, `99`). Varios datos se
repiten en todos: usuario de Docker Hub, nombre y tags de la imagen, namespace,
contexto de Kubernetes, y las funciones de presentación.

### Opciones evaluadas

| Opción | Valoración |
|--------|-----------|
| Repetir las variables en cada script | Seis sitios que actualizar al cambiar de usuario de Docker Hub. Garantiza que antes o después se desincronizan. |
| Variables de entorno (`$env:DOCKERHUB_USER`) | Se pierden al cerrar la terminal y obligan a un paso previo manual. |
| **Un `00-config.ps1` cargado con *dot-sourcing*** | Un único punto de verdad. |

### Decisión
Añadir **`scripts/00-config.ps1`** (y `scripts/00-extraer-ca-corporativa.ps1`,
ver [ADR-09](#adr-09--inyección-de-la-ca-corporativa-de-inspección-tls)). Son
dos archivos **por encima** de la estructura solicitada; el resto se respeta
íntegramente. Se numeran `00-` para dejar claro que son previos y auxiliares.

Contenido: variables compartidas, funciones de presentación
(`Write-Fase`/`Write-Paso`/`Write-Ok`/`Write-Falla`/`Write-Info`), el guard
`Assert-ContextoMinikube` y la reparación del `PATH` para localizar `minikube`.

### Consecuencias

**Positivas**
- Cambiar de usuario de Docker Hub es editar **una línea**.
- La salida de todos los scripts es visualmente homogénea, lo que mejora las
  capturas de pantalla.
- El guard de seguridad del [ADR-10](#adr-10--contexto-de-kubectl-explícito-en-todos-los-scripts)
  vive en un solo sitio.

**Negativas**
- Los scripts `01`…`99` **no son autónomos**: dependen de `00-config.ps1`. Se
  mitiga porque todos lo cargan en su segunda línea con
  `. "$PSScriptRoot\00-config.ps1"`, que resuelve la ruta relativa al propio
  script y funciona desde cualquier directorio de trabajo.

**Detalle resuelto aquí:** `minikube.exe` se instaló en `%USERPROFILE%\bin` y esa
carpeta se añadió al PATH de **usuario** (`HKCU`, sin admin). Pero un proceso ya
en marcha **no ve ese cambio**: hereda el PATH que tenía su padre al arrancar.
Síntoma: `The term 'minikube' is not recognized`. `00-config.ps1` añade la
carpeta a `$env:Path` si hace falta, para que los scripts funcionen en cualquier
terminal sin tener que reiniciarla.
