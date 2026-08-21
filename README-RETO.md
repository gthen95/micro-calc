# Reto 5 — Docker, Docker Hub y Minikube

Microservicio calculadora (Spring Boot 4.1.0 / Java 21) empaquetado en una imagen
Docker, publicado en Docker Hub y desplegado en Kubernetes sobre Minikube, con la
configuración externalizada en un ConfigMap.

- **Fork:** <https://github.com/gthen95/micro-calc>
- **Imagen:** <https://hub.docker.com/r/gthen95/micro-calc> · `gthen95/micro-calc:1.0.0`
- **Digest:** `sha256:3aecbb12d624817e375456aa8a6ac47ac30de3104f255366d89ad2c297e65173`

---

## Quickstart

```powershell
git clone https://github.com/gthen95/micro-calc.git C:\dev\micro-calc; cd C:\dev\micro-calc
.\scripts\00-extraer-ca-corporativa.ps1   # solo si tu red hace inspeccion TLS (ver nota)
.\scripts\01-build-local.ps1              # construye la imagen y la prueba en Docker
docker login -u <TU_USUARIO_DOCKERHUB>    # con un Personal Access Token, no la contrasena
.\scripts\02-push-dockerhub.ps1           # publica :1.0.0, :latest y :<sha> y lo verifica
.\scripts\03-minikube-up.ps1              # arranca el clúster + metrics-server
.\scripts\04-deploy.ps1                   # kubectl apply -f k8s/ y espera el rollout
.\scripts\05-pruebas.ps1                  # pruebas, resiliencia, HPA y escalado
kubectl --context minikube port-forward -n micro-calc svc/micro-calc 8081:80
# -> abre http://localhost:8081/  y debe responder: gerald-k8s,k8s-minikube
.\scripts\99-cleanup.ps1                  # limpieza (pide confirmacion)
```

Para usar **tu** cuenta de Docker Hub, edita una sola línea en
`scripts/00-config.ps1` (`$Global:DOCKERHUB_USER`) y el campo `image:` de
`k8s/02-deployment.yaml`.

---

## Requisitos

| Herramienta | Versión mínima | Notas |
|-------------|---------------|-------|
| Rancher Desktop | cualquiera | Container Engine = **dockerd (moby)**; Kubernetes propio **desactivado** |
| Minikube | 1.38+ | Se instala sin admin: binario en `%USERPROFILE%\bin` + PATH de usuario |
| kubectl | 1.32+ | |
| PowerShell | 5.1 o 7.x | Probado en 7.6.5 |
| Java / Maven en el host | **no hacen falta** | Los aporta la etapa `build` del contenedor |
| Permisos de administrador | **no hacen falta** | |

---

## Qué demuestra el reto

La **misma imagen** da tres respuestas distintas en `GET /` según de dónde venga
la configuración:

| Origen de la configuración | `GET /` devuelve |
|---------------------------|------------------|
| `application.properties` empaquetado en el JAR | `admin,localhost` |
| Variables de `docker run -e ...` | `gerald,docker-local` |
| **ConfigMap de Kubernetes** | **`gerald-k8s,k8s-minikube`** |

Eso es la externalización de configuración: *build once, deploy anywhere*.

---

## Endpoints

| Método | Ruta | Respuesta |
|--------|------|-----------|
| GET | `/` | `db.user,db.server` (texto plano) |
| GET | `/suma/{a}/{b}` | `{"a":7,"b":5,"error":"NO","resultado":12}` |
| GET | `/resta/{a}/{b}` | `{"a":10,"b":3,"error":"NO","resultado":7}` |
| GET | `/div/{a}/{b}` | `{"a":10,"b":2,"error":"NO","resultado":5}` |
| GET | `/div/{a}/0` | `{"a":10,"b":0,"error":"<mensaje configurado>","resultado":0}` |

---

## Estructura

```
Dockerfile              Multi-stage: build (JDK21+Maven3.9) -> runtime (no-root, UID 10001)
.dockerignore
certs/                  CA corporativa de inspeccion TLS (contenido *.crt NO se publica)
k8s/
  00-namespace.yaml     Namespace micro-calc
  01-configmap.yaml     DB_USER, DB_SERVER, APP_MESSAGE_ERROR
  02-deployment.yaml    2 replicas, probes, resources, securityContext, RollingUpdate
  03-service.yaml       NodePort 80 -> 8080 (nodePort 30080)
  04-hpa.yaml           autoscaling/v2, 2-5 replicas, CPU 70%
scripts/
  00-config.ps1                  Variables compartidas + guard de contexto
  00-extraer-ca-corporativa.ps1  Exporta la CA de inspeccion TLS del almacen de Windows
  01-build-local.ps1             Build + run + pruebas + verificacion de endurecimiento
  02-push-dockerhub.ps1          Push de los 3 tags + verificacion contra el registro
  03-minikube-up.ps1             minikube start + metrics-server + CA en el nodo
  04-deploy.ps1                  kubectl apply + rollout + diagnostico
  05-pruebas.ps1                 3 metodos de acceso + resiliencia + HPA + escalado
  99-cleanup.ps1                 Limpieza escalonada y confirmada
docs/
  00-entorno.md         Diagnostico del entorno y de la red
  DECISIONES.md         12 ADR (contexto / opciones / decision / consecuencias)
  EVIDENCIAS.md         Guia de las 26 capturas para el PDF
  evidencias.html       Documento imprimible (Ctrl+P -> Microsoft Print to PDF)
```

---

## Resultados medidos

| Métrica | Valor |
|---------|-------|
| Build completo sin caché | 167,8 s |
| Tests | `Tests run: 1, Failures: 0, Errors: 0` → **BUILD SUCCESS** |
| Tamaño real de la imagen | **220,6 MB** (`docker image inspect .Size`) |
| Capas en la imagen final | 6 |
| Arranque de Minikube | 117,3 s |
| Arranque de Spring Boot en el Pod | ~3,8 s |
| Consumo por Pod | 2m CPU · 117 MiB (límites: 500m / 512 Mi) |
| Heap con `--memory=512m` | 384 MiB (75 %) ✅ |

---

## Notas importantes del entorno

### Red con inspección TLS

Si tu red corporativa hace *deep inspection* SSL, el build fallará con
`PKIX path building failed` y los Pods quedarán en `ImagePullBackOff` con
`x509: certificate signed by unknown authority`. **Es la misma causa raíz:** los
contenedores traen su propio almacén de certificados y no confían en la CA de la
empresa, aunque Windows sí.

Solución (no requiere admin):
```powershell
.\scripts\00-extraer-ca-corporativa.ps1
```
El `Dockerfile` y `03-minikube-up.ps1` la inyectan donde hace falta. Fuera de una
red así, no hace falta ejecutarlo: el build lo detecta y sigue funcionando.
Detalle completo en `docs/DECISIONES.md` (ADR-09).

### Contexto de `kubectl`

Todos los scripts usan **`--context minikube` explícito** y validan el contexto
antes de actuar. Si tu `~/.kube/config` tiene clústeres de trabajo, es imposible
que estos scripts los toquen. Ver ADR-10.

### NodePort desde Windows

`http://<minikube-ip>:30080` normalmente **no responde** desde el navegador de
Windows: con `--driver=docker` el nodo es un contenedor dentro de la VM WSL2 y su
IP no es enrutable desde el host. Usa `kubectl port-forward`. Ver ADR-06.

---

## Licencia y atribución

Fork de <https://github.com/gmacastil/micro-calc>. El código fuente de la
aplicación (`src/`) y el `pom.xml` **no se han modificado**. Todo lo añadido
—`Dockerfile`, `k8s/`, `scripts/`, `docs/`— es trabajo del reto.
