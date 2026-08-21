# =====================================================================
# 00-config.ps1 — Variables compartidas del Reto 5
# Se carga con dot-sourcing desde los demas scripts:  . "$PSScriptRoot\00-config.ps1"
# NO se ejecuta por si solo.
# =====================================================================

# --- Identidad del proyecto -------------------------------------------------
$Global:FORK_URL       = "https://github.com/gthen95/micro-calc"
$Global:DOCKERHUB_USER = "gthen95"
$Global:IMAGE_NAME     = "micro-calc"
$Global:IMAGE_VERSION  = "1.0.0"
$Global:IMAGE_REPO     = "$Global:DOCKERHUB_USER/$Global:IMAGE_NAME"
$Global:IMAGE_TAGGED   = "$Global:IMAGE_REPO`:$Global:IMAGE_VERSION"
$Global:IMAGE_LATEST   = "$Global:IMAGE_REPO`:latest"

# --- Kubernetes -------------------------------------------------------------
$Global:K8S_NAMESPACE  = "micro-calc"
$Global:K8S_CONTEXT    = "minikube"          # contexto OBLIGATORIO (ver guard mas abajo)
$Global:K8S_DEPLOYMENT = "micro-calc"
$Global:K8S_SERVICE    = "micro-calc"

# --- Rutas ------------------------------------------------------------------
$Global:REPO_ROOT      = Split-Path -Parent $PSScriptRoot

# --- Raiz del proyecto: siempre trabajar desde ahi ---------------------------
Set-Location $Global:REPO_ROOT

# =====================================================================
# PATH: localizar minikube sin depender del entorno heredado
# =====================================================================
# minikube.exe se instalo en %USERPROFILE%\bin y esa carpeta se anadio al PATH
# de USUARIO (HKCU), que no requiere permisos de administrador. Pero un proceso
# ya en marcha NO ve ese cambio: hereda el PATH que tenia su padre al arrancar.
# Sintoma tipico: "The term 'minikube' is not recognized...".
# Se anaden aqui las rutas conocidas si el ejecutable no se encuentra, para que
# los scripts funcionen en cualquier terminal sin tener que reiniciarla.
foreach ($carpeta in @("$env:USERPROFILE\bin", "$env:LOCALAPPDATA\Microsoft\WindowsApps")) {
    if ((Test-Path $carpeta) -and ($env:Path -notlike "*$carpeta*")) {
        $env:Path = "$env:Path;$carpeta"
    }
}
if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    Write-Warning "minikube no se encuentra en el PATH. Instalalo con:"
    Write-Warning '  New-Item -ItemType Directory -Force "$env:USERPROFILE\bin" | Out-Null; Invoke-WebRequest -Uri "https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube-windows-amd64.exe" -OutFile "$env:USERPROFILE\bin\minikube.exe"'
}

# =====================================================================
# Utilidades de presentacion (salida legible para capturas de pantalla)
# =====================================================================
function Write-Fase {
    param([string]$Texto)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host "  $Texto" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Paso {
    param([string]$Texto)
    Write-Host ""
    Write-Host ">>> $Texto" -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkGray
}

function Write-Ok    { param([string]$T) Write-Host "  [OK]    $T" -ForegroundColor Green }
function Write-Falla { param([string]$T) Write-Host "  [FALLA] $T" -ForegroundColor Red }
function Write-Info  { param([string]$T) Write-Host "  [INFO]  $T" -ForegroundColor Gray }

# =====================================================================
# GUARD DE SEGURIDAD - CRITICO
# En esta maquina el contexto activo de kubectl es un clúster AKS corporativo
# real (aks-corporativo-REDACTADO). Aplicar los manifiestos ahi por
# error desplegaria el reto academico en infraestructura de produccion/dev
# corporativa. Todo script que hable con Kubernetes DEBE llamar a esta funcion
# antes de cualquier kubectl, y ademas usar siempre --context minikube.
# =====================================================================
function Assert-ContextoMinikube {
    $actual = (kubectl config current-context 2>$null)
    Write-Info "Contexto activo de kubectl: '$actual'"
    if ($actual -ne $Global:K8S_CONTEXT) {
        Write-Host ""
        Write-Host "  !!! ADVERTENCIA DE SEGURIDAD !!!" -ForegroundColor Red
        Write-Host "  El contexto activo NO es '$Global:K8S_CONTEXT', es '$actual'." -ForegroundColor Red
        Write-Host "  Todos los comandos de este script usan --context $Global:K8S_CONTEXT" -ForegroundColor Yellow
        Write-Host "  de forma explicita, por lo que NO se tocara '$actual'." -ForegroundColor Yellow
        Write-Host ""
    }
    $existe = (kubectl config get-contexts -o name 2>$null) -contains $Global:K8S_CONTEXT
    if (-not $existe) {
        Write-Falla "No existe el contexto '$Global:K8S_CONTEXT'. Ejecuta antes scripts\03-minikube-up.ps1"
        throw "Contexto '$Global:K8S_CONTEXT' inexistente."
    }
    Write-Ok "Contexto '$Global:K8S_CONTEXT' disponible. Se usara de forma explicita en cada comando."
}

# Atajo: kubectl siempre apuntado a minikube
function kc { kubectl --context $Global:K8S_CONTEXT @args }
