<#
.SYNOPSIS
    Limpieza del entorno del reto.
.DESCRIPTION
    Elimina, de forma escalonada y CONFIRMADA, los recursos creados durante el
    reto. Por defecto solo borra lo del clúster; hay que pedir explicitamente
    borrar el clúster o las imagenes.
.EXAMPLE
    .\scripts\99-cleanup.ps1
    Borra el namespace micro-calc y el contenedor local. Deja el clúster.
.EXAMPLE
    .\scripts\99-cleanup.ps1 -Todo
    Borra ademas el clúster de Minikube y las imagenes locales.
.NOTES
    SEGURIDAD: todos los kubectl llevan --context minikube EXPLICITO, para que
    sea imposible borrar nada del clúster AKS corporativo.
#>
[CmdletBinding()]
param(
    [switch]$BorrarNamespace = $true,   # namespace micro-calc del clúster
    [switch]$BorrarContenedor = $true,  # contenedor local de la FASE 3
    [switch]$BorrarClúster,             # minikube delete
    [switch]$BorrarImagenes,            # imagenes locales gthen95/micro-calc
    [switch]$BorrarCertificados,        # certs/*.crt generados localmente
    [switch]$Todo,                      # todo lo anterior
    [switch]$SinConfirmar               # no preguntar
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot\00-config.ps1"

if ($Todo) {
    $BorrarNamespace = $true; $BorrarContenedor = $true
    $BorrarClúster = $true;   $BorrarImagenes = $true
}

$ns  = $Global:K8S_NAMESPACE
$ctx = $Global:K8S_CONTEXT

Write-Fase "LIMPIEZA DEL ENTORNO DEL RETO"

# --- Resumen de lo que se va a hacer, ANTES de tocar nada -------------------
Write-Host "  Se va a eliminar:" -ForegroundColor Yellow
if ($BorrarNamespace)    { Write-Host "   - Namespace '$ns' del clúster '$ctx' (Pods, Service, ConfigMap, HPA)" -ForegroundColor Yellow }
if ($BorrarContenedor)   { Write-Host "   - Contenedor local 'micro-calc' (FASE 3)" -ForegroundColor Yellow }
if ($BorrarClúster)      { Write-Host "   - EL CLUSTER COMPLETO de Minikube (minikube delete)" -ForegroundColor Red }
if ($BorrarImagenes)     { Write-Host "   - Imagenes locales $($Global:IMAGE_REPO) (NO se borra nada de Docker Hub)" -ForegroundColor Yellow }
if ($BorrarCertificados) { Write-Host "   - Certificados locales certs\*.crt" -ForegroundColor Yellow }
Write-Host ""
Write-Host "  NO se toca:" -ForegroundColor Green
Write-Host "   - El repositorio de Docker Hub ni sus tags publicados" -ForegroundColor Green
Write-Host "   - El clúster AKS corporativo (todo lleva --context $ctx)" -ForegroundColor Green
Write-Host "   - El codigo fuente ni los manifiestos del repositorio" -ForegroundColor Green
Write-Host ""

if (-not $SinConfirmar) {
    $r = Read-Host "  Escribe SI para continuar"
    if ($r -ne "SI") { Write-Info "Cancelado. No se ha borrado nada."; exit 0 }
}

# =============================================================================
if ($BorrarNamespace) {
    Write-Paso "1. Eliminando el namespace '$ns'"
    # Borrar el namespace arrastra TODO lo que hay dentro: Deployment,
    # ReplicaSets, Pods, Service, ConfigMap y HPA. Es la ventaja de haber usado
    # un namespace dedicado en vez de 'default'.
    $existe = (kubectl config get-contexts -o name 2>$null) -contains $ctx
    if (-not $existe) {
        Write-Info "El contexto '$ctx' no existe. Nada que borrar en el clúster."
    } else {
        kubectl --context $ctx delete namespace $ns --ignore-not-found --wait=true
        Write-Ok "Namespace '$ns' eliminado"
    }
}

# =============================================================================
if ($BorrarContenedor) {
    Write-Paso "2. Eliminando el contenedor local de la FASE 3"
    docker rm -f micro-calc 2>&1 | Out-Null
    Write-Ok "Contenedor 'micro-calc' eliminado (si existia)"
}

# =============================================================================
if ($BorrarClúster) {
    Write-Paso "3. Eliminando el clúster de Minikube"
    Write-Info "Esto borra el nodo entero. Volver a crearlo tarda ~2 minutos."
    minikube delete
    Write-Ok "Clúster eliminado"
}

# =============================================================================
if ($BorrarImagenes) {
    Write-Paso "4. Eliminando las imagenes locales"
    Write-Info "IMPORTANTE: esto NO borra nada de Docker Hub. La imagen publicada"
    Write-Info "sigue disponible en https://hub.docker.com/r/$($Global:IMAGE_REPO)"
    $SHA = (git rev-parse --short HEAD 2>$null)
    foreach ($t in @($Global:IMAGE_VERSION, "latest", $SHA)) {
        if ($t) {
            docker rmi ($Global:IMAGE_REPO + ":" + $t) 2>&1 | Out-Null
            Write-Ok "Eliminada: $($Global:IMAGE_REPO):$t"
        }
    }
}

# =============================================================================
if ($BorrarCertificados) {
    Write-Paso "5. Eliminando los certificados locales"
    Write-Info "Se regeneran cuando haga falta con 00-extraer-ca-corporativa.ps1"
    Get-ChildItem (Join-Path $Global:REPO_ROOT "certs") -Filter "*.crt" -ErrorAction SilentlyContinue |
        Remove-Item -Force
    Write-Ok "certs\*.crt eliminados"
}

Write-Host ""
Write-Fase "LIMPIEZA COMPLETADA"
Write-Info "Estado actual del entorno:"
docker ps -a --filter "name=micro-calc" --format "table {{.Names}}\t{{.Status}}"
if ((kubectl config get-contexts -o name 2>$null) -contains $ctx) {
    kubectl --context $ctx get namespaces 2>&1 | Select-String -Pattern "micro-calc" -NotMatch:$false | Out-Null
    kubectl --context $ctx get all -n $ns 2>&1 | Select-Object -First 3
}
