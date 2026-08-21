<#
.SYNOPSIS
    FASE 6 - Arranca el clúster de Minikube y habilita metrics-server.
.DESCRIPTION
    Crea un clúster local de un nodo usando el driver `docker`, que reutiliza el
    daemon de Rancher Desktop. Habilita metrics-server (necesario para el HPA) y
    muestra el estado del clúster.
.NOTES
    POR QUE --driver=docker Y NO --driver=hyperv
    -------------------------------------------
    hyperv exige pertenecer al grupo "Hyper-V Administrators" o ser
    administrador local, y en este equipo NO hay permisos de administrador.
    Ademas Hyper-V y WSL2 comparten el hipervisor, y arrancar una segunda VM
    junto a la de Rancher Desktop duplicaria el consumo de RAM.

    Con --driver=docker el "nodo" de Kubernetes es un CONTENEDOR que corre en el
    daemon que ya esta en marcha: sin elevacion, sin VM adicional, y arranca en
    menos de un minuto.
#>
[CmdletBinding()]
param(
    [int]$Cpus     = 2,
    [int]$MemoriaMB = 4096,
    [switch]$Recrear   # borra el clúster existente antes de crear uno nuevo
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\00-config.ps1"

Write-Fase "FASE 6 - ARRANQUE DE MINIKUBE"

# =============================================================================
Write-Paso "0. Requisitos previos"
# =============================================================================
docker info --format '{{.ServerVersion}}' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Falla "El daemon de Docker no responde. Abre Rancher Desktop y espera a 'Running'."
    exit 1
}
Write-Ok "Daemon de Docker operativo (driver=docker lo va a reutilizar)"

$v = (minikube version --short 2>$null)
Write-Ok "minikube $v"

if ($Recrear) {
    Write-Info "Modo -Recrear: eliminando el clúster anterior..."
    minikube delete 2>&1 | Out-Null
    Write-Ok "Clúster anterior eliminado"
}

# =============================================================================
Write-Paso "0-bis. Sembrando la CA corporativa para el NODO"
# =============================================================================
# Minikube copia automaticamente todo lo que haya en %USERPROFILE%\.minikube\certs
# al nodo durante `minikube start`, y ejecuta update-ca-certificates. Hay que
# dejar los certificados AHI ANTES de arrancar para que un clúster creado desde
# cero ya nazca confiando en la CA.
$certsRepo = Join-Path $Global:REPO_ROOT "certs"
$certsMk   = Join-Path $env:USERPROFILE ".minikube\certs"
$listaCrt  = @(Get-ChildItem $certsRepo -Filter "corp-ca-*.crt" -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -ne "corp-ca-bundle.crt" })

if ($listaCrt.Count -eq 0) {
    Write-Info "No hay certificados en certs\. Si esta red no intercepta TLS, es lo correcto."
    Write-Info "Si el pull de imagenes fallara con 'certificate signed by unknown authority',"
    Write-Info "ejecuta antes: .\scripts\00-extraer-ca-corporativa.ps1"
} else {
    if (-not (Test-Path $certsMk)) { New-Item -ItemType Directory -Path $certsMk -Force | Out-Null }
    foreach ($c in $listaCrt) { Copy-Item $c.FullName (Join-Path $certsMk $c.Name) -Force }
    Write-Ok "$($listaCrt.Count) certificado(s) copiados a $certsMk"
    Write-Info "minikube los instalara en el nodo durante el start."
}

# =============================================================================
Write-Paso "1. minikube start"
# =============================================================================
# No se pasan flags de proxy: en esta red no hay proxy (verificado en
# docs/00-entorno.md). Tampoco hace falta inyectar la CA corporativa en el nodo:
# minikube descarga sus imagenes de registry.k8s.io y gcr.io, y ambos estan
# EXENTOS de la inspeccion TLS del FortiGate (emisor real: Google Trust
# Services). La interceptacion solo afecta a Maven Central y GitHub.
$argsStart = @(
    "start",
    "--driver=docker",
    "--cpus=$Cpus",
    "--memory=$MemoriaMB",
    "--kubernetes-version=stable"
)

Write-Host "  Comando: minikube $($argsStart -join ' ')" -ForegroundColor DarkCyan
Write-Host ""
$t0 = Get-Date
& minikube @argsStart
if ($LASTEXITCODE -ne 0) {
    Write-Falla "minikube start fallo."
    Write-Host ""
    Write-Host "  DIAGNOSTICO HABITUAL:" -ForegroundColor Yellow
    Write-Host "   - 'Exiting due to RSRC_INSUFFICIENT_CORES' -> baja -Cpus" -ForegroundColor Yellow
    Write-Host "   - 'not enough memory'  -> baja -MemoriaMB, o revisa %USERPROFILE%\.wslconfig" -ForegroundColor Yellow
    Write-Host "   - el nodo se queda a medias -> .\scripts\03-minikube-up.ps1 -Recrear" -ForegroundColor Yellow
    exit 1
}
$dur = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
Write-Ok "Clúster arrancado en $dur segundos"

# =============================================================================
Write-Paso "1-bis. Confirmando que el NODO confia en la CA corporativa"
# =============================================================================
# POR QUE ESTE PASO EXISTE
# ------------------------
# El nodo de Minikube es un contenedor Debian recien creado con su PROPIO
# almacen de certificados. Aunque Windows y la distro WSL2 de Rancher Desktop si
# confien en la CA del FortiGate, el nodo no. Sintoma exacto observado el
# 2026-08-21 al desplegar por primera vez:
#
#   Failed to pull image "gthen95/micro-calc:1.0.0":
#   Get "https://auth.docker.io/token?...": tls: failed to verify certificate:
#   x509: certificate signed by unknown authority
#   -> los Pods quedan en ImagePullBackOff
#
# Es exactamente la misma causa raiz que rompio Maven en la FASE 3: el FortiGate
# intercepta auth.docker.io. Este paso lo repara EN CALIENTE, de forma
# idempotente, para que funcione tambien en un clúster que ya estuviera creado
# antes de sembrar los certificados en 0-bis.
if ($listaCrt.Count -gt 0) {
    $bundle = Join-Path $certsRepo "corp-ca-bundle.crt"
    Get-Content ($listaCrt | ForEach-Object { $_.FullName }) | Set-Content $bundle -Encoding ascii

    minikube cp $bundle "/tmp/corp-ca-bundle.crt" 2>&1 | Out-Null
    minikube ssh -- "sudo cp /tmp/corp-ca-bundle.crt /usr/local/share/ca-certificates/corp-ca-bundle.crt && sudo update-ca-certificates >/dev/null 2>&1 && sudo systemctl restart docker" 2>&1 | Out-Null

    Start-Sleep -Seconds 8
    Write-Ok "CA instalada en el nodo y daemon del nodo reiniciado"

    Write-Info "Comprobando que el nodo puede descargar la imagen del registro..."
    $prueba = minikube ssh -- "docker pull $($Global:IMAGE_TAGGED) 2>&1 | tail -2" 2>&1 | Out-String
    if ($prueba -match "Downloaded newer image|Image is up to date") {
        Write-Ok "El NODO descarga correctamente desde Docker Hub"
    } else {
        Write-Falla "El nodo aun no puede descargar la imagen:"
        Write-Host $prueba -ForegroundColor Red
        Write-Info "Plan B offline disponible: .\scripts\04-deploy.ps1 -CargarImagenOffline"
    }
}

# =============================================================================
Write-Paso "2. Habilitando metrics-server (imprescindible para el HPA)"
# =============================================================================
Write-Info "Sin metrics-server el HPA muestra TARGETS = <unknown>/70% de forma permanente."
minikube addons enable metrics-server
if ($LASTEXITCODE -ne 0) {
    Write-Falla "No se pudo habilitar metrics-server. El HPA quedara en <unknown>."
} else {
    Write-Ok "Addon metrics-server habilitado"
    Write-Info "Tarda entre 30 y 60 s en recopilar la primera muestra. <unknown> durante ese rato es NORMAL."
}

# =============================================================================
Write-Paso "3. minikube status"
# =============================================================================
minikube status

# =============================================================================
Write-Paso "4. Contextos de kubectl (COMPROBACION DE SEGURIDAD)"
# =============================================================================
kubectl config get-contexts
Write-Host ""
Assert-ContextoMinikube

# =============================================================================
Write-Paso "5. kubectl get nodes -o wide"
# =============================================================================
kubectl --context $Global:K8S_CONTEXT get nodes -o wide

# =============================================================================
Write-Paso "6. kubectl cluster-info"
# =============================================================================
kubectl --context $Global:K8S_CONTEXT cluster-info

# =============================================================================
Write-Paso "7. Datos del nodo"
# =============================================================================
$ip = (minikube ip 2>$null)
Write-Ok "IP del nodo de Minikube: $ip"
Write-Info "OJO: esa IP pertenece a una red bridge de Docker que vive DENTRO de la"
Write-Info "VM WSL2. Desde el navegador de Windows normalmente NO es alcanzable."
Write-Info "Para probar desde Windows se usa kubectl port-forward (ver 05-pruebas.ps1)."

Write-Host ""
Write-Fase "FASE 6 - MINIKUBE LISTO"
Write-Ok "Siguiente paso: .\scripts\04-deploy.ps1"
