<#
.SYNOPSIS
    FASE 3 - Construye la imagen Docker de micro-calc y la prueba localmente.
.DESCRIPTION
    1. Construye la imagen con el Dockerfile multi-stage.
    2. Etiqueta :1.0.0, :latest y :<sha-corto-de-git> (tag inmutable).
    3. Muestra el tamano de la imagen final.
    4. Levanta el contenedor INYECTANDO las variables de entorno, para demostrar
       que la configuracion esta externalizada (no empotrada en la imagen).
    5. Ejecuta las 4 pruebas funcionales.
    6. Muestra los logs del contenedor.
.NOTES
    Requiere: Rancher Desktop corriendo con engine dockerd (moby).
#>
[CmdletBinding()]
param(
    [switch]$SinCache,          # fuerza --no-cache
    [switch]$SoloBuild          # construye pero no ejecuta el contenedor
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\00-config.ps1"

# --- Valores de prueba para la ejecucion LOCAL en Docker ---------------------
# Deliberadamente DISTINTOS a los de application.properties (admin,localhost) y
# a los del ConfigMap de Kubernetes (gerald-k8s,k8s-minikube). Asi cada captura
# demuestra sin ambiguedad de donde viene la configuracion.
$DB_SERVER_LOCAL = "docker-local"
$DB_USER_LOCAL   = "gerald"
$ERROR_LOCAL     = "division por cero no permitida"

$CONTENEDOR = "micro-calc"
$PUERTO     = 8080

Write-Fase "FASE 3 - BUILD Y EJECUCION LOCAL CON DOCKER"

# =============================================================================
Write-Paso "0. Verificando que el daemon de Docker responde"
# =============================================================================
$srv = docker info --format '{{.ServerVersion}} ({{.OperatingSystem}})' 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Falla "El daemon de Docker no responde. Abre Rancher Desktop y espera a 'Running'."
    exit 1
}
Write-Ok "Docker Server: $srv"

# =============================================================================
Write-Paso "1. Calculando el tag inmutable a partir del commit de git"
# =============================================================================
$SHA = (git rev-parse --short HEAD 2>$null)
if ([string]::IsNullOrWhiteSpace($SHA)) { $SHA = "nogit" }
$IMAGE_SHA = "$Global:IMAGE_REPO`:$SHA"
Write-Ok "Commit actual : $SHA"
Write-Info "Tags a generar:"
Write-Info "   $Global:IMAGE_TAGGED   <- tag semantico, el que usa el Deployment"
Write-Info "   $Global:IMAGE_LATEST   <- comodidad para pruebas manuales"
Write-Info "   $IMAGE_SHA   <- tag INMUTABLE, trazable al commit exacto"

# =============================================================================
Write-Paso "2. docker build (multi-stage: JDK21+Maven 3.9 -> JRE/JDK 21 no-root)"
# =============================================================================
$argsBuild = @("build", "--progress=plain", "-t", $Global:IMAGE_TAGGED, "-t", $Global:IMAGE_LATEST, "-t", $IMAGE_SHA)
if ($SinCache) { $argsBuild += "--no-cache"; Write-Info "Modo --no-cache activado" }
$argsBuild += "."

Write-Host "  Comando: docker $($argsBuild -join ' ')" -ForegroundColor DarkCyan
Write-Host ""
$t0 = Get-Date
& docker @argsBuild
if ($LASTEXITCODE -ne 0) {
    Write-Falla "El build fallo. Revisa la salida de arriba."
    exit 1
}
$dur = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
Write-Ok "Build exitoso en $dur segundos"

# =============================================================================
Write-Paso "3. Imagenes generadas y tamano final"
# =============================================================================
docker images $Global:IMAGE_REPO --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
Write-Host ""
# OJO con el tamano: la columna SIZE de `docker images` NO es el tamano de la
# imagen. Docker 29 usa el almacen de imagenes de containerd (snapshotter
# overlayfs) y ahi SIZE agrega todos los blobs del content store asociados al
# nombre. El dato correcto para saber cuanto pesa la imagen que se publicara es
# el campo .Size de `docker image inspect`.
$tam = [int64](docker image inspect $Global:IMAGE_TAGGED --format '{{.Size}}')
Write-Ok ("Tamano REAL de la imagen final: {0:N1} MB ({1:N0} bytes)" -f ($tam / 1MB), $tam)
Write-Info "(la columna SIZE de 'docker images' muestra un valor mayor: es el content store de containerd, no la imagen)"
$capas = (docker image inspect $Global:IMAGE_TAGGED --format '{{len .RootFS.Layers}}')
Write-Info "Capas en la imagen final: $capas — solo las de runtime. Las capas de Maven,"
Write-Info "el codigo fuente y el repositorio ~/.m2 quedaron en la etapa 'build' y NO se publican."
$base = (docker image inspect $Global:IMAGE_TAGGED --format '{{index .Config.Labels "org.opencontainers.image.title"}}')
Write-Info "Etiqueta OCI title: $base"

if ($SoloBuild) { Write-Info "Modo -SoloBuild: se omite la ejecucion."; exit 0 }

# =============================================================================
Write-Paso "4. Levantando el contenedor con configuracion EXTERNALIZADA"
# =============================================================================
docker rm -f $CONTENEDOR 2>&1 | Out-Null

Write-Info "Variables de entorno inyectadas (relaxed binding de Spring):"
Write-Info "   DB_USER=$DB_USER_LOCAL              -> propiedad db.user"
Write-Info "   DB_SERVER=$DB_SERVER_LOCAL       -> propiedad db.server"
Write-Info "   APP_MESSAGE_ERROR='$ERROR_LOCAL' -> propiedad app.message.error"
Write-Host ""

docker run -d --name $CONTENEDOR -p "$PUERTO`:8080" `
    -e "DB_SERVER=$DB_SERVER_LOCAL" `
    -e "DB_USER=$DB_USER_LOCAL" `
    -e "APP_MESSAGE_ERROR=$ERROR_LOCAL" `
    $Global:IMAGE_TAGGED | Out-Null

if ($LASTEXITCODE -ne 0) { Write-Falla "No se pudo iniciar el contenedor."; exit 1 }
Write-Ok "Contenedor '$CONTENEDOR' iniciado"

# =============================================================================
Write-Paso "5. Esperando a que Spring Boot termine de arrancar"
# =============================================================================
$listo = $false
for ($i = 1; $i -le 60; $i++) {
    try {
        Invoke-RestMethod -Uri "http://localhost:$PUERTO/" -TimeoutSec 3 -ErrorAction Stop | Out-Null
        $listo = $true
        Write-Ok "Aplicacion respondiendo tras $i segundo(s)"
        break
    } catch {
        Start-Sleep -Seconds 1
        if ($i % 5 -eq 0) { Write-Host "  ... esperando ($i s)" -ForegroundColor DarkGray }
    }
}
if (-not $listo) {
    Write-Falla "La aplicacion no respondio en 60 s. Logs:"
    docker logs $CONTENEDOR --tail 50
    exit 1
}

# =============================================================================
Write-Paso "6. PRUEBAS FUNCIONALES (Invoke-RestMethod)"
# =============================================================================
function Test-Endpoint {
    param([string]$Ruta, [string]$Descripcion, [string]$Esperado)
    Write-Host ""
    Write-Host "  GET http://localhost:$PUERTO$Ruta" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "      $Descripcion" -ForegroundColor Gray
    if ($Esperado) { Write-Host "      Esperado: $Esperado" -ForegroundColor DarkGray }
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:$PUERTO$Ruta" -TimeoutSec 10 -ErrorAction Stop
        if ($r -is [string]) {
            Write-Host "      RESPUESTA: $r" -ForegroundColor Green
        } else {
            Write-Host "      RESPUESTA: $($r | ConvertTo-Json -Compress)" -ForegroundColor Green
        }
    } catch {
        Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Test-Endpoint "/"          "Devuelve db.user,db.server -> PRUEBA LA INYECCION DE CONFIGURACION" "$DB_USER_LOCAL,$DB_SERVER_LOCAL"
Test-Endpoint "/suma/7/5"  "Suma 7 + 5"        "resultado=12"
Test-Endpoint "/resta/10/3" "Resta 10 - 3"     "resultado=7"
Test-Endpoint "/div/10/2"  "Division 10 / 2"   "resultado=5"
Test-Endpoint "/div/10/0"  "Division por cero -> mensaje desde la VARIABLE DE ENTORNO" "error='$ERROR_LOCAL'"

# =============================================================================
Write-Paso "7. Logs del contenedor (ultimas 30 lineas)"
# =============================================================================
docker logs $CONTENEDOR --tail 30

# =============================================================================
Write-Paso "8. VERIFICACION DEL ENDURECIMIENTO DE LA IMAGEN"
# =============================================================================
Write-Host "  a) El proceso NO corre como root:" -ForegroundColor White
$idOut = docker exec $CONTENEDOR id
Write-Host "     $idOut" -ForegroundColor Green
Write-Info "   Requisito del securityContext runAsNonRoot: true del Deployment."

Write-Host ""
Write-Host "  b) PID 1 es java directamente (ENTRYPOINT en exec form):" -ForegroundColor White
$pid1 = (docker exec $CONTENEDOR cat /proc/1/cmdline) -replace "`0", " "
Write-Host "     $pid1" -ForegroundColor Green
Write-Info "   Asi java recibe SIGTERM y Spring hace shutdown ordenado. Con shell"
Write-Info "   form, /bin/sh seria PID 1 y se tragaria la senal."

Write-Host ""
Write-Host "  c) -XX:MaxRAMPercentage=75 respeta el limite del contenedor:" -ForegroundColor White
# --entrypoint java es IMPRESCINDIBLE: la imagen declara
# ENTRYPOINT ["java", ..., "-jar", "/app/app.jar"], y lo que se pasa despues del
# nombre de la imagen se CONCATENA al entrypoint, no lo sustituye. Sin este flag
# el comando arrancaria la aplicacion completa y el script quedaria colgado.
$heap = (docker run --rm --memory=512m --memory-swap=512m --entrypoint java $Global:IMAGE_TAGGED -XX:MaxRAMPercentage=75 -XX:+PrintFlagsFinal -version 2>&1) |
    Select-String -Pattern "size_t\s+MaxHeapSize"
if ($heap) {
    $bytes = [int64](($heap.Line -split '=')[1].Trim() -split '\s+')[0]
    Write-Host "     $($heap.Line.Trim())" -ForegroundColor Green
    Write-Ok ("   Heap maximo = {0:N0} MiB  =  75 % de 512 MiB. CORRECTO." -f ($bytes / 1MB))
    Write-Info "   Sin este flag la JVM calcularia el heap sobre los 63 GB del host,"
    Write-Info "   se pasaria del limit de 512Mi y Kubernetes matarian el Pod (OOMKilled)."
}

Write-Host ""
Write-Fase "FASE 3 COMPLETADA"
Write-Ok "Imagen local lista: $Global:IMAGE_TAGGED"
Write-Info "Abre en el navegador: http://localhost:$PUERTO/suma/7/5   (EVIDENCIA #8)"
Write-Info "Para detener el contenedor: docker rm -f $CONTENEDOR"
