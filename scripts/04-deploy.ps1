<#
.SYNOPSIS
    FASE 6 (2 de 2) - Despliega los manifiestos en Minikube.
.DESCRIPTION
    Aplica k8s/ completo, espera el rollout y muestra el estado de los recursos.
    Si algun Pod queda en ImagePullBackOff, ofrece el plan B offline
    (`minikube image load`) y explica la diferencia con el pull desde registro.
.NOTES
    SEGURIDAD: todos los kubectl llevan --context minikube EXPLICITO. En este
    equipo el contexto por defecto puede ser un clúster AKS corporativo real.
#>
[CmdletBinding()]
param(
    # Aplica el plan B offline directamente, sin esperar a que falle el pull.
    [switch]$CargarImagenOffline,
    # Borra los recursos y los vuelve a crear desde cero.
    [switch]$Recrear
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\00-config.ps1"

$ns  = $Global:K8S_NAMESPACE
$ctx = $Global:K8S_CONTEXT

Write-Fase "FASE 6 (2 de 2) - DESPLIEGUE EN KUBERNETES"

# =============================================================================
Write-Paso "0. Comprobacion de seguridad del contexto"
# =============================================================================
Assert-ContextoMinikube

# Aviso de desfase de versiones cliente/servidor (informativo, no bloqueante).
$vCli = (kubectl version --client -o json 2>$null | ConvertFrom-Json).clientVersion.gitVersion
$vSrv = (kubectl --context $ctx version -o json 2>$null | ConvertFrom-Json).serverVersion.gitVersion
Write-Info "kubectl cliente: $vCli   |   API server: $vSrv"
if ($vCli -and $vSrv) {
    $mCli = [int](($vCli -replace '^v(\d+)\.(\d+).*', '$2'))
    $mSrv = [int](($vSrv -replace '^v(\d+)\.(\d+).*', '$2'))
    if ([math]::Abs($mSrv - $mCli) -gt 1) {
        Write-Info "Hay mas de una version menor de diferencia. Kubernetes soporta +/-1."
        Write-Info "Para estas operaciones no supone problema; si aparecieran rarezas,"
        Write-Info "usa el kubectl que trae minikube:  minikube kubectl -- get pods -n $ns"
    }
}

if ($Recrear) {
    Write-Paso "0-bis. Modo -Recrear: eliminando el namespace"
    kubectl --context $ctx delete namespace $ns --ignore-not-found --wait=true
    Write-Ok "Namespace '$ns' eliminado"
}

# =============================================================================
Write-Paso "1. kubectl apply -f k8s/"
# =============================================================================
# Los archivos se aplican en orden alfabetico, por eso van numerados: el
# namespace (00-) debe existir antes que los objetos que viven dentro de el.
Write-Host "  Comando: kubectl --context $ctx apply -f k8s/" -ForegroundColor DarkCyan
Write-Host ""
kubectl --context $ctx apply -f k8s/
if ($LASTEXITCODE -ne 0) {
    Write-Falla "Fallo el apply. Revisa la salida."
    exit 1
}
Write-Ok "Manifiestos aplicados"

# =============================================================================
if ($CargarImagenOffline) {
    Write-Paso "1-bis. PLAN B - carga directa de la imagen en el nodo"
    Write-Info "minikube image load copia la imagen desde el daemon del host"
    Write-Info "al almacen de imagenes del NODO, sin pasar por ningun registro."
    minikube image load $Global:IMAGE_TAGGED
    Write-Ok "Imagen cargada en el nodo"
    kubectl --context $ctx rollout restart deployment/$Global:K8S_DEPLOYMENT -n $ns
}

# =============================================================================
Write-Paso "2. Esperando el rollout del Deployment"
# =============================================================================
kubectl --context $ctx rollout status deployment/$Global:K8S_DEPLOYMENT -n $ns --timeout=300s
$rolloutOk = ($LASTEXITCODE -eq 0)

if (-not $rolloutOk) {
    Write-Falla "El rollout no termino en 300 s. Diagnosticando..."
    Write-Host ""
    kubectl --context $ctx get pods -n $ns -o wide
    Write-Host ""

    # ¿Es un problema de descarga de la imagen?
    $estados = kubectl --context $ctx get pods -n $ns -o jsonpath='{range .items[*]}{.status.containerStatuses[*].state.waiting.reason}{"\n"}{end}' 2>$null
    if ($estados -match "ImagePullBackOff|ErrImagePull") {
        Write-Host ""
        Write-Host "  DIAGNOSTICO: ImagePullBackOff / ErrImagePull" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  PULL DESDE REGISTRO vs CARGA DIRECTA AL NODO" -ForegroundColor Cyan
        Write-Host "  -------------------------------------------" -ForegroundColor Cyan
        Write-Host "  Pull desde registro (lo normal):" -ForegroundColor Cyan
        Write-Host "    El kubelet del NODO contacta con registry-1.docker.io y se baja" -ForegroundColor Cyan
        Write-Host "    las capas. El nodo necesita salida a Internet y, si el repo fuera" -ForegroundColor Cyan
        Write-Host "    privado, un imagePullSecret. Es como funciona en produccion." -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Cyan
        Write-Host "  minikube image load (plan B offline):" -ForegroundColor Cyan
        Write-Host "    Exporta la imagen del daemon del HOST y la inyecta directamente en" -ForegroundColor Cyan
        Write-Host "    el almacen de imagenes del NODO. No interviene ningun registro." -ForegroundColor Cyan
        Write-Host "    Solo funciona porque el nodo es local; en un clúster real no existe" -ForegroundColor Cyan
        Write-Host "    esta via. Requiere imagePullPolicy: IfNotPresent o Never, porque" -ForegroundColor Cyan
        Write-Host "    con Always el kubelet ignoraria la copia local." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  SOLUCION: .\scripts\04-deploy.ps1 -CargarImagenOffline" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Info "No parece un problema de imagen. Eventos del namespace:"
        kubectl --context $ctx get events -n $ns --sort-by=.lastTimestamp | Select-Object -Last 20
    }
    exit 1
}
Write-Ok "Rollout completado: todas las replicas estan Ready"

# =============================================================================
Write-Paso "3. kubectl get all,configmap,hpa -n $ns"
# =============================================================================
kubectl --context $ctx get all,configmap,hpa -n $ns

# =============================================================================
Write-Paso "4. Detalle de los Pods"
# =============================================================================
kubectl --context $ctx get pods -n $ns -o wide

# =============================================================================
Write-Paso "5. Comprobacion: la imagen que corre es la de Docker Hub"
# =============================================================================
$imagenes = kubectl --context $ctx get pods -n $ns -o jsonpath='{range .items[*]}{.metadata.name}{"  ->  "}{.spec.containers[0].image}{"\n"}{end}'
Write-Host $imagenes
$idImagen = kubectl --context $ctx get pods -n $ns -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
Write-Ok "imageID resuelto en el nodo:"
Write-Host "     $idImagen" -ForegroundColor Green
Write-Info "Si incluye el digest sha256 de Docker Hub, la imagen se descargo del registro."

# =============================================================================
Write-Paso "6. Endpoints del Service (deben coincidir con las IP de los Pods)"
# =============================================================================
Write-Info "Un Service sin Endpoints es el fallo silencioso mas comun: significa"
Write-Info "que el selector no coincide con las labels del Pod."
kubectl --context $ctx get endpointslices -n $ns -o wide

Write-Host ""
Write-Fase "FASE 6 COMPLETADA - APLICACION DESPLEGADA"
Write-Ok "Siguiente paso: .\scripts\05-pruebas.ps1"
