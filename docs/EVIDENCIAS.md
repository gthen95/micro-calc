# Guía de evidencias para el PDF

**Reto 5 — Diplomado de Arquitectura de Software (Módulo 5: Docker, Docker Hub y
Minikube)**
Autor: Gerald Then · Fork: <https://github.com/gthen95/micro-calc> ·
Docker Hub: <https://hub.docker.com/r/gthen95/micro-calc>

---

## Cómo usar este documento

1. Ejecuta los scripts en orden (§ *Secuencia de ejecución*).
2. Ve tomando las capturas **en el momento indicado** en la columna
   *«Momento exacto»*: muchas solo son reproducibles justo después de un comando
   concreto (por ejemplo, ver un Pod en `ContainerCreating`).
3. Pega cada captura en `docs/evidencias.html`, que ya trae el hueco, el comando
   y el texto explicativo redactados. Ábrelo en el navegador y usa
   **Ctrl+P → «Microsoft Print to PDF»** (gratuito, sin Acrobat).

> **Nota sobre el mapeo de entregables.** El enunciado pide mapear las capturas a
> «los 8 entregables». Como no se dispone del listado literal del módulo, se ha
> usado la descomposición natural del reto que aparece abajo. **Si tu módulo
> nombra los entregables de otra forma, renombra la columna «Entregable» — el
> contenido de las capturas no cambia.**

| # | Entregable | Capturas |
|---|-----------|----------|
| **E1** | Entorno preparado (Rancher Desktop, Docker, Minikube) | 1, 2, 13, 14 |
| **E2** | Fork del repositorio en GitHub | 3 |
| **E3** | Dockerfile funcional | 4, 5 |
| **E4** | Imagen construida y probada en local | 6, 7, 8, 25 |
| **E5** | Imagen publicada en Docker Hub | 9, 10, 11 |
| **E6** | Manifiestos de Kubernetes | 12, 15, 18 |
| **E7** | Despliegue funcionando en Minikube | 16, 17, 19, 20 |
| **E8** | Operación: logs, resiliencia, escalado, autoescalado | 21, 22, 23, 24, 26 |

---

## Reglas para TODAS las capturas

| Regla | Motivo |
|-------|--------|
| **PowerShell maximizado**, fuente **≥ 14 pt** | Al reducir la imagen en el PDF, una fuente pequeña se vuelve ilegible. Se cambia en: clic derecho en la barra de título → *Propiedades* → *Fuente*. |
| **Tema claro** (fondo blanco, texto negro) | Un fondo negro consume tinta y se imprime mal. En Windows Terminal: `Ctrl+,` → *Perfiles* → *Apariencia* → esquema **One Half Light**. |
| **El comando SIEMPRE visible encima de su salida** | Sin el comando, la salida no demuestra nada. |
| **Reloj de Windows visible** | Demuestra la cronología: que los pasos ocurrieron en secuencia y no son capturas sueltas. |
| **Censurar** tokens, correos corporativos y dominios internos | Ver la lista concreta más abajo. |
| Herramienta: **Win+Shift+S** (Recorte de Windows) | Nativo y gratuito. Pega directamente en el HTML o en Word. |

### Qué hay que censurar en este proyecto concreto

| Elemento | Dónde puede aparecer | Cómo |
|----------|---------------------|------|
| **Personal Access Token de Docker Hub** | Captura 9 | `docker login` **no lo imprime** (la entrada es oculta). Solo verifica que no quede pegado en el historial visible. |
| **Correo corporativo** | Prompt de git, `git config` | Tapar con rectángulo negro. |
| **Nombre del clúster AKS corporativo** | Captura 13 (`kubectl config get-contexts`) | Tapar la fila `aks-…`. **Sí conviene dejar visible que existe otro contexto**: refuerza el argumento del `--context minikube` explícito. |
| **Números de serie de los FortiGate** | Solo si abres `certs/` | No hace falta capturarlos. |
| Ruta `C:\Users\u30951\...` | Casi todas | Es el usuario de Windows, no un secreto. Se puede dejar. |

---

## Secuencia de ejecución

```powershell
cd C:\dev\micro-calc
.\scripts\00-extraer-ca-corporativa.ps1     # solo dentro de la red corporativa
.\scripts\01-build-local.ps1                # capturas 5, 6, 7, 25
docker login -u gthen95                     # captura 9
.\scripts\02-push-dockerhub.ps1             # captura 10
.\scripts\03-minikube-up.ps1                # capturas 13, 14
.\scripts\04-deploy.ps1                     # capturas 15, 16, 17
.\scripts\05-pruebas.ps1                    # capturas 19, 20, 21, 22, 23, 24, 26
```

---

# Tabla de capturas

---

### 1 · Versiones de las herramientas

| | |
|---|---|
| **Entregable** | E1 — Entorno preparado |
| **Momento** | Al principio de todo, antes de tocar nada. |

**Comando:**
```powershell
git --version; docker --version; docker compose version; java --version; kubectl version --client; minikube version
```

**Qué debe verse:** las seis salidas seguidas en la misma ventana. Como mínimo
`git version 2.47.1.windows.1`, `Docker version 29.5.3-rd`, `kubectl v1.34.6` y
`minikube version: v1.38.1`.

**Texto para el PDF:**
> Inventario de las herramientas del entorno de trabajo. El sufijo `-rd` de la
> versión de Docker confirma que el CLI lo provee **Rancher Desktop**, no Docker
> Desktop, evitando así el requisito de licencia comercial para empresas. Java
> local es la 17, insuficiente para Spring Boot 4; esto no bloquea el proyecto
> porque el JDK 21 lo aporta la etapa `build` del contenedor.

---

### 2 · Rancher Desktop en «Running» con engine dockerd

| | |
|---|---|
| **Entregable** | E1 — Entorno preparado |
| **Momento** | Con la ventana de Rancher Desktop abierta. |

**Cómo:** abre Rancher Desktop → pestaña **Preferences → Container Engine**.
Toma **dos capturas** o una que muestre ambas cosas:
- La ventana principal con el indicador **«Running»** abajo a la izquierda.
- `Container Engine = dockerd (moby)` **seleccionado**.
- `Preferences → Kubernetes` con **«Enable Kubernetes» DESMARCADO**.

**Texto para el PDF:**
> Rancher Desktop operativo con el motor **dockerd (moby)**, imprescindible para
> que el CLI `docker` funcione (con `containerd` habría que usar `nerdctl`). El
> Kubernetes propio de Rancher Desktop se ha **desactivado** a propósito: si
> quedara activo registraría su propio contexto en `~/.kube/config` y competiría
> con el de Minikube, con riesgo real de desplegar en el clúster equivocado.

---

### 3 · Fork del repositorio en GitHub

| | |
|---|---|
| **Entregable** | E2 — Fork |
| **Momento** | Antes de clonar. |

**Cómo:** navegador en `https://github.com/gthen95/micro-calc`.

**Qué debe verse:** la **URL completa en la barra de direcciones** y la leyenda
*«forked from gmacastil/micro-calc»* bajo el título del repositorio.

**Texto para el PDF:**
> Fork personal del repositorio base. La leyenda «forked from» acredita la
> trazabilidad con el proyecto original. Todo el trabajo posterior (Dockerfile,
> manifiestos y scripts) se añade sobre este fork sin modificar el código fuente
> de la aplicación.

---

### 4 · Dockerfile abierto en VS Code

| | |
|---|---|
| **Entregable** | E3 — Dockerfile |
| **Momento** | Cualquiera. |

**Cómo:** `code C:\dev\micro-calc` y abre el `Dockerfile`. Conviene tomar **dos**
capturas: una de la etapa `build` (con el bloque de caché de dependencias) y otra
de la etapa `runtime` (usuario 10001 y `ENTRYPOINT`).

**Qué debe verse:** el explorador lateral con la estructura (`k8s/`, `scripts/`,
`docs/`, `Dockerfile`, `.dockerignore`) y las dos sentencias `FROM`.

**Texto para el PDF:**
> Dockerfile **multi-stage**. La etapa `build` compila con JDK 21 y Maven 3.9
> dentro del contenedor, de modo que la máquina anfitriona no necesita ni Java 21
> ni Maven. La etapa `runtime` recibe únicamente el JAR: ni el código fuente, ni
> Maven, ni el repositorio `~/.m2` llegan a la imagen publicada.

---

### 5 · `docker build` completo

| | |
|---|---|
| **Entregable** | E3 — Dockerfile |
| **Momento** | Durante `.\scripts\01-build-local.ps1`, paso 2. |

**Comando:**
```powershell
.\scripts\01-build-local.ps1 -SinCache
```

**Qué debe verse:** las capas numeradas (`#1`, `#2`, …), la línea
`[CA] Importando 22 certificado(s) de CA corporativa...`, el bloque de Maven con
`Tests run: 1, Failures: 0, Errors: 0` y `BUILD SUCCESS`, y al final
`[OK] Build exitoso en NNN segundos`.

**Texto para el PDF:**
> Construcción completa de la imagen. Se aprecia la separación en dos etapas y la
> ejecución de los tests **dentro del build**: `contextLoads()` valida que el
> contexto de Spring levanta correctamente antes de empaquetar. Build medido:
> **167,8 s** sin caché; con caché de dependencias, los rebuilds bajan a segundos.

---

### 6 · `docker images` con la imagen y su tamaño

| | |
|---|---|
| **Entregable** | E4 — Imagen local |
| **Momento** | Paso 3 de `01-build-local.ps1`. |

**Comando:**
```powershell
docker images gthen95/micro-calc --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"; docker image inspect gthen95/micro-calc:1.0.0 --format '{{.Size}}'
```

**Qué debe verse:** los tres tags (`1.0.0`, `latest`, `ffd72bc`) con el **mismo
Image ID**, y la línea `[OK] Tamaño REAL de la imagen final: 220,6 MB`.

**Texto para el PDF:**
> Los tres tags apuntan al **mismo Image ID**: son nombres distintos de la misma
> imagen, no tres copias. Nota técnica importante: la columna `SIZE` de
> `docker images` muestra **733 MB**, que **no** es el tamaño de la imagen —
> Docker 29 usa el almacén de containerd y esa columna agrega todos los blobs del
> *content store*. El dato correcto es el campo `.Size` de `docker image
> inspect`: **220,6 MB**, coincidente con lo que reporta Docker Hub.

---

### 7 · `docker run` y las respuestas JSON

| | |
|---|---|
| **Entregable** | E4 — Imagen local |
| **Momento** | Pasos 4–6 de `01-build-local.ps1`. |

**Qué debe verse:** el bloque `[INFO] Variables de entorno inyectadas`, seguido de
las cinco pruebas. Imprescindibles:
```
GET http://localhost:8080/          RESPUESTA: gerald,docker-local
GET http://localhost:8080/div/10/0  RESPUESTA: {"a":10,"b":0,"error":"division por cero no permitida","resultado":0}
```

**Texto para el PDF:**
> La aplicación corriendo en Docker con la **configuración inyectada por
> variables de entorno**. `GET /` devuelve `gerald,docker-local`, valores que
> **no** están en la imagen (el `application.properties` empaquetado dice
> `admin,localhost`). Esto demuestra el *relaxed binding* de Spring Boot:
> `DB_USER` → `db.user`, `DB_SERVER` → `db.server`.

---

### 8 · Navegador contra el contenedor local

| | |
|---|---|
| **Entregable** | E4 — Imagen local |
| **Momento** | Con el contenedor de la FASE 3 en marcha. |

**Cómo:** abre `http://localhost:8080/suma/7/5` y, en otra pestaña,
`http://localhost:8080/`.

**Qué debe verse:** la URL en la barra y el JSON
`{"a":7,"b":5,"error":"NO","resultado":12}`.

**Texto para el PDF:**
> Verificación desde el navegador de que el contenedor publica correctamente el
> puerto 8080 en el host. El campo `error: "NO"` es el valor por defecto de la
> clase `Respuesta` cuando la operación es válida.

---

### 9 · `docker login` correcto

| | |
|---|---|
| **Entregable** | E5 — Docker Hub |
| **Momento** | Antes del push. |

**Comando:**
```powershell
docker login -u gthen95
```

**Qué debe verse:** el prompt `Password:` (vacío, sin eco) y la respuesta
**`Login Succeeded`**.

⚠️ **El token nunca se muestra en pantalla**, así que la captura es segura tal
cual. Comprueba solo que no quede pegado más arriba en el historial visible.

**Texto para el PDF:**
> Autenticación contra Docker Hub mediante **Personal Access Token**, no
> contraseña. En entornos corporativos con SSO el CLI suele rechazar la
> contraseña, y además el token es revocable de forma independiente sin cambiar
> las credenciales de la cuenta.

---

### 10 · `docker push` completo

| | |
|---|---|
| **Entregable** | E5 — Docker Hub |
| **Momento** | Paso 2 de `02-push-dockerhub.ps1`. |

**Comando:**
```powershell
.\scripts\02-push-dockerhub.ps1
```

**Qué debe verse:** las capas subiendo (`Pushed`), y las tres líneas de digest —
**idéntico en los tres tags**:
```
1.0.0:   digest: sha256:3aecbb12d624817e375456aa8a6ac47ac30de3104f255366d89ad2c297e65173
latest:  digest: sha256:3aecbb12...
ffd72bc: digest: sha256:3aecbb12...
```
Y al final, el paso 4: `Imagen BORRADA del disco local` → `docker pull` →
`[OK] LOS IDENTIFICADORES COINCIDEN`.

**Texto para el PDF:**
> Publicación de los tres tags. Solo el primer `push` sube capas; los otros dos
> son instantáneos porque apuntan al mismo digest. La verificación **no se
> conforma con que el push no diera error**: el script borra la imagen del disco
> local y la vuelve a descargar, comprobando que el identificador coincide. Eso
> descarta que estuviéramos viendo una caché local en vez del registro.

---

### 11 · Repositorio en hub.docker.com con los tags

| | |
|---|---|
| **Entregable** | E5 — Docker Hub |
| **Momento** | Tras el push. |

**Cómo:** navegador en `https://hub.docker.com/r/gthen95/micro-calc/tags`.

**Qué debe verse:** los tres tags `1.0.0`, `latest` y `ffd72bc`, el tamaño
**220.6 MB** en cada uno, y la etiqueta **Public** junto al nombre del repositorio.

**Texto para el PDF:**
> Imagen publicada y **pública**. La visibilidad pública es un requisito
> funcional, no cosmético: permite que el kubelet de Minikube haga `pull` sin
> necesidad de un `imagePullSecret`. Los 220,6 MB coinciden exactamente con lo
> medido en local, lo que confirma que se subió la imagen correcta.

---

### 12 · Carpeta `k8s/` en VS Code

| | |
|---|---|
| **Entregable** | E6 — Manifiestos |
| **Momento** | Cualquiera. |

**Cómo:** en VS Code, despliega `k8s/` y abre `02-deployment.yaml`.

**Qué debe verse:** los cinco YAML numerados en el explorador y, en el editor, el
bloque `image: gthen95/micro-calc:1.0.0` junto con `resources` y los tres probes.

**Texto para el PDF:**
> Los cinco manifiestos. La numeración `00`–`04` no es decorativa: `kubectl apply
> -f k8s/` procesa los archivos en **orden alfabético**, y el Namespace debe
> existir antes que los objetos que viven dentro de él.

---

### 13 · `minikube start` y `minikube status`

| | |
|---|---|
| **Entregable** | E1 — Entorno preparado |
| **Momento** | Durante `.\scripts\03-minikube-up.ps1`. |

**Qué debe verse:** el arranque con los emojis de minikube, la línea
`Using the docker driver based on user configuration`, `minikube status` con
`host: Running / kubelet: Running / apiserver: Running`, y el bloque
`kubectl config get-contexts`.

⚠️ **Censura la fila del clúster `aks-…`**, pero deja visible que existe.

**Texto para el PDF:**
> Clúster arrancado con `--driver=docker` en **117,3 s**. Este driver no requiere
> permisos de administrador (a diferencia de `--driver=hyperv`, que exige
> pertenecer al grupo *Hyper-V Administrators*) y reutiliza la VM WSL2 que
> Rancher Desktop ya tiene en marcha, en vez de levantar una segunda. En la lista
> de contextos se aprecia que el contexto activo del sistema podía ser otro
> clúster; por eso **todos los scripts usan `--context minikube` explícito**.

---

### 14 · `kubectl get nodes -o wide`

| | |
|---|---|
| **Entregable** | E1 — Entorno preparado |
| **Momento** | Paso 5 de `03-minikube-up.ps1`. |

**Comando:**
```powershell
kubectl --context minikube get nodes -o wide
```

**Qué debe verse:**
```
NAME       STATUS   ROLES           VERSION   INTERNAL-IP    OS-IMAGE                        CONTAINER-RUNTIME
minikube   Ready    control-plane   v1.35.1   192.168.49.2   Debian GNU/Linux 12 (bookworm)  docker://29.2.1
```

**Texto para el PDF:**
> Nodo único en estado `Ready` haciendo de *control-plane*. `OS-IMAGE` revela que
> el «nodo» es en realidad un **contenedor Debian 12** dentro de la VM WSL2, y el
> `KERNEL-VERSION` (`…microsoft-standard-WSL2`) lo confirma. La IP `192.168.49.2`
> pertenece a una red bridge interna a esa VM: esa es la razón técnica de que el
> NodePort no sea alcanzable directamente desde Windows.

---

### 15 · `kubectl apply -f k8s/`

| | |
|---|---|
| **Entregable** | E6 — Manifiestos |
| **Momento** | Paso 1 de `04-deploy.ps1`. |

**Qué debe verse:** las **cinco** líneas de creación:
```
namespace/micro-calc created
configmap/micro-calc-config created
deployment.apps/micro-calc created
service/micro-calc created
horizontalpodautoscaler.autoscaling/micro-calc created
```

**Texto para el PDF:**
> Aplicación declarativa de los cinco recursos con un único comando. `kubectl
> apply` es **idempotente**: al volver a ejecutarlo, los recursos sin cambios
> aparecen como `unchanged` en vez de `created`, que es la base del modelo de
> «estado deseado» de Kubernetes.

---

### 16 · `kubectl get all -n micro-calc` con los Pods en Running

| | |
|---|---|
| **Entregable** | E7 — Despliegue |
| **Momento** | Paso 3 de `04-deploy.ps1`. |

**Comando:**
```powershell
kubectl --context minikube get all,configmap,hpa -n micro-calc
```

**Qué debe verse:** dos Pods `1/1 Running` con `RESTARTS 0`, el Deployment
`2/2`, el Service `NodePort 80:30080/TCP`, el ReplicaSet `2 2 2` y el HPA.

**Texto para el PDF:**
> Estado completo del namespace. `READY 1/1` significa que el contenedor pasó el
> `readinessProbe`; `RESTARTS 0` confirma que el `startupProbe` dio a la JVM
> tiempo suficiente para arrancar y el `livenessProbe` no la mató durante el
> arranque — el error más habitual al desplegar aplicaciones Java en Kubernetes.

---

### 17 · `kubectl describe pod` — imagen y probes

| | |
|---|---|
| **Entregable** | E7 — Despliegue |
| **Momento** | Sección *describe pod* de `05-pruebas.ps1`. |

**Comando:**
```powershell
kubectl --context minikube describe pod -n micro-calc $(kubectl --context minikube get pods -n micro-calc -o jsonpath='{.items[0].metadata.name}')
```

**Qué debe verse (tres zonas, quizá en dos capturas):**
1. `Image: gthen95/micro-calc:1.0.0` y
   `Image ID: docker-pullable://gthen95/micro-calc@sha256:3aecbb12...`
2. Las tres líneas `Liveness:`, `Readiness:` y `Startup:` con sus parámetros.
3. Los `Events` con `Pulling` → `Pulled` → `Created` → `Started`.

**Texto para el PDF:**
> Evidencia de que la imagen se descargó **realmente de Docker Hub**: el
> `Image ID` contiene el digest `sha256:3aecbb12…`, exactamente el mismo que
> devolvió `docker push`. Se ven además los tres probes configurados y los
> eventos del ciclo de vida, sin errores ni reinicios.

---

### 18 · `kubectl get configmap -o yaml`

| | |
|---|---|
| **Entregable** | E6 — Manifiestos |
| **Momento** | Cualquiera tras el despliegue. |

**Comando:**
```powershell
kubectl --context minikube get configmap micro-calc-config -n micro-calc -o yaml
```

**Qué debe verse:** el bloque `data:` con las tres claves:
```yaml
data:
  APP_MESSAGE_ERROR: Division por cero no permitida (valor desde ConfigMap)
  DB_SERVER: k8s-minikube
  DB_USER: gerald-k8s
```

**Texto para el PDF:**
> Configuración externalizada, viviendo en el clúster como un objeto propio y
> **fuera de la imagen**. Los nombres de las claves siguen el *relaxed binding*
> de Spring Boot: `DB_USER` se liga a `db.user`, `APP_MESSAGE_ERROR` a
> `app.message.error`. Las variables de entorno tienen más prioridad que el
> `application.properties` empaquetado, por eso estos valores ganan.

---

### 19 · ⭐ Navegador mostrando `gerald-k8s,k8s-minikube`

| | |
|---|---|
| **Entregable** | E7 — Despliegue |
| **Momento** | Con el túnel de port-forward abierto. |

**Cómo — deja este comando corriendo en una terminal aparte:**
```powershell
kubectl --context minikube port-forward -n micro-calc svc/micro-calc 8081:80
```
Y abre en el navegador `http://localhost:8081/`.

**Qué debe verse:** la URL en la barra y, como único contenido de la página, el
texto **`gerald-k8s,k8s-minikube`**.

> 💡 **La captura más importante del reto.** Si puedes, ponla al lado de la
> captura 8 (`gerald,docker-local`) en la misma página del PDF: el contraste es
> el argumento entero.

**Texto para el PDF:**
> **Evidencia central del reto.** La misma imagen que en Docker devolvía
> `gerald,docker-local` ahora devuelve `gerald-k8s,k8s-minikube`. Los tres
> orígenes posibles de configuración dan tres resultados distintos:
> `application.properties` dentro del JAR → `admin,localhost`; variables de
> `docker run` → `gerald,docker-local`; **ConfigMap de Kubernetes** →
> `gerald-k8s,k8s-minikube`. Queda demostrado sin ambigüedad que la configuración
> viene del ConfigMap y no está empotrada en la imagen.

---

### 20 · `/div/10/0` con el mensaje del ConfigMap

| | |
|---|---|
| **Entregable** | E7 — Despliegue |
| **Momento** | Con el túnel abierto. |

**Cómo:** navegador en `http://localhost:8081/div/10/0`, o desde PowerShell:
```powershell
Invoke-RestMethod http://localhost:8081/div/10/0 | ConvertTo-Json
```

**Qué debe verse:**
```json
{"a":10,"b":0,"error":"Division por cero no permitida (valor desde ConfigMap)","resultado":0}
```

**Texto para el PDF:**
> Segunda evidencia del ConfigMap. El `application.properties` original contiene
> `"no se puede divir por cero, da infinito"` **con comillas literales incluidas
> en el valor**; el mensaje mostrado es distinto y sin comillas, lo que confirma
> que se está leyendo la clave `APP_MESSAGE_ERROR` del ConfigMap y no el fichero
> empaquetado.

---

### 21 · `kubectl logs`

| | |
|---|---|
| **Entregable** | E8 — Operación |
| **Momento** | Sección *kubectl logs* de `05-pruebas.ps1`. |

**Comando:**
```powershell
kubectl --context minikube logs -n micro-calc -l app.kubernetes.io/name=micro-calc --tail=20 --prefix
```

**Qué debe verse:** el banner de Spring Boot con `:: Spring Boot :: (v4.1.0)`, la
línea `Starting DemoMicroApplication ... using Java 21.0.12.1 with PID 1`, y
`Started DemoMicroApplication in N seconds`. El prefijo `[pod/nombre/micro-calc]`
debe aparecer en cada línea.

**Texto para el PDF:**
> Logs agregados de **todos** los Pods mediante el selector de etiquetas
> `-l app.kubernetes.io/name=micro-calc`, sin nombrar ningún Pod concreto. Se
> confirma Spring Boot 4.1.0 sobre Java 21 y, crucialmente, **`PID 1`**: gracias
> al `ENTRYPOINT` en *exec form*, el proceso `java` es PID 1 y recibe `SIGTERM`
> directamente, lo que permite un apagado ordenado cuando Kubernetes retira el
> Pod.

---

### 22 · Borrado de un Pod y su recreación automática

| | |
|---|---|
| **Entregable** | E8 — Operación |
| **Momento** | Sección *prueba de resiliencia* de `05-pruebas.ps1`. |

**Comando:**
```powershell
kubectl --context minikube delete pod <nombre> -n micro-calc; kubectl --context minikube get pods -n micro-calc -o wide
```

**Qué debe verse — una sola captura con las tres fases seguidas:**
- `ANTES:` dos Pods `Running` con edades parecidas.
- `INMEDIATAMENTE DESPUÉS:` uno `Terminating` y otro en `ContainerCreating` o
  `Pending`.
- `DESPUÉS:` dos Pods `Running` de nuevo, pero uno con `AGE` de pocos segundos.

⚠️ Esta captura hay que hacerla **rápido**: la ventana de `ContainerCreating` dura
unos segundos.

**Texto para el PDF:**
> Prueba de autorreparación. Quien recrea el Pod **no es el Deployment sino el
> ReplicaSet**: su bucle de reconciliación detecta que hay 1 Pod donde deberían
> haber 2 y crea uno nuevo en segundos. La columna `AGE` delata cuál es el Pod
> nuevo. El servicio nunca se interrumpió: la otra réplica siguió atendiendo
> peticiones durante todo el incidente.

---

### 23 · `kubectl get hpa` con métricas disponibles

| | |
|---|---|
| **Entregable** | E8 — Operación |
| **Momento** | Sección *Estado del HPA* de `05-pruebas.ps1`, **tras la espera activa**. |

**Comando:**
```powershell
kubectl --context minikube get hpa -n micro-calc; kubectl --context minikube top pods -n micro-calc
```

**Qué debe verse:** `TARGETS` con un valor real, **no `<unknown>`**:
```
NAME         REFERENCE               TARGETS      MINPODS   MAXPODS   REPLICAS
micro-calc   Deployment/micro-calc   cpu: 1%/70%  2         5         2
```
Y debajo, `kubectl top pods` con el consumo real (≈`2m` de CPU y `117Mi` de
memoria por Pod).

**Texto para el PDF:**
> HPA operativo con métricas reales. Que aparezca `1%/70%` y no `<unknown>/70%`
> demuestra dos requisitos cumplidos: (1) el addon **metrics-server** está
> habilitado, y (2) el contenedor **declara `resources.requests.cpu`** — el HPA
> calcula la utilización como *uso ÷ request*, y sin request la métrica sería
> indefinida. El objetivo del 70 % sobre un request de 200m equivale a 140m por
> Pod. El consumo de memoria (117 MiB) queda holgadamente por debajo del límite
> de 512 Mi.

---

### 24 · `kubectl scale` a 4 réplicas

| | |
|---|---|
| **Entregable** | E8 — Operación |
| **Momento** | Sección *prueba de escalado* de `05-pruebas.ps1`. |

**Comando:**
```powershell
kubectl --context minikube scale deployment micro-calc --replicas=4 -n micro-calc; kubectl --context minikube get pods -n micro-calc -o wide
```

**Qué debe verse:** los cuatro Pods `1/1 Running` con IPs distintas, y debajo el
`EndpointSlice` con las cuatro direcciones.

**Texto para el PDF:**
> Escalado horizontal manual de 2 a 4 réplicas. Los `EndpointSlice` del Service
> se actualizan **automáticamente** para incluir las cuatro IPs: no hay que tocar
> el Service, porque su `selector` de etiquetas es dinámico. Después se vuelve a
> 2 réplicas, que es el `minReplicas` que exige el HPA.

---

### 25 · Endurecimiento de la imagen (opcional, muy recomendable)

| | |
|---|---|
| **Entregable** | E4 — Imagen local |
| **Momento** | Paso 8 de `01-build-local.ps1`. |

**Qué debe verse:**
```
a) uid=10001(spring) gid=10001(spring) groups=10001(spring)
b) java -XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError -jar /app/app.jar
c) size_t MaxHeapSize = 402653184
   [OK] Heap maximo = 384 MiB = 75 % de 512 MiB. CORRECTO.
```

**Texto para el PDF:**
> Verificación empírica de tres decisiones de diseño: el proceso corre como
> **usuario no privilegiado** (UID 10001, requisito de `runAsNonRoot: true`);
> **`java` es PID 1** gracias al `ENTRYPOINT` en *exec form*; y
> **`-XX:MaxRAMPercentage=75` respeta el límite del contenedor** — con
> `--memory=512m` la JVM se asigna 384 MiB de heap. Sin ese flag calcularía el
> heap sobre los 63 GB del anfitrión, superaría el `limit` de 512 Mi y Kubernetes
> mataría el Pod con `OOMKilled`.

---

### 26 · Acceso desde dentro del clúster (opcional)

| | |
|---|---|
| **Entregable** | E8 — Operación |
| **Momento** | Método 3 de `05-pruebas.ps1`. |

**Comando:**
```powershell
kubectl --context minikube run tester --rm -i --restart=Never --image=curlimages/curl:8.11.1 -n micro-calc -- -s http://micro-calc.micro-calc.svc.cluster.local/suma/2/3
```

**Qué debe verse:** `{"a":2,"b":3,"error":"NO","resultado":5}` seguido de
`pod "tester" deleted`.

**Texto para el PDF:**
> Prueba desde **dentro** del clúster, que elimina por completo la red del host
> de la ecuación. Un Pod efímero resuelve el nombre DNS completo
> `micro-calc.micro-calc.svc.cluster.local` (formato
> `servicio.namespace.svc.cluster.local`) y llama al ClusterIP. Confirma que el
> Service y el DNS interno funcionan con independencia de si el host Windows
> alcanza o no el NodePort.

---

## Anexo · Capturas adicionales sugeridas

Si el PDF admite un apartado de incidencias, estas dos aportan mucho valor porque
documentan **problemas reales resueltos**, no un camino feliz:

| Captura extra | Comando | Por qué vale la pena |
|---------------|---------|---------------------|
| **A · El fallo de TLS en Maven** | Salida del primer `docker build`, con `PKIX path building failed` | Documenta el diagnóstico del FortiGate y justifica el ADR-09 y el ADR-11. Demuestra que no se degradó Spring Boot 4.1.0 a lo tonto. |
| **B · Los Pods en `ImagePullBackOff`** | `kubectl get pods -n micro-calc` + `kubectl get events` mostrando `x509: certificate signed by unknown authority` | Es **la misma causa raíz** que el fallo A, manifestándose en otra capa. Excelente material para la sección de lecciones aprendidas. |

Ambos fallos y sus soluciones están documentados en `docs/DECISIONES.md`
(ADR-09) y en `docs/00-entorno.md` (§4).
