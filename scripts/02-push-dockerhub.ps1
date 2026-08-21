<#
.SYNOPSIS
    FASE 4 - Publica la imagen en Docker Hub y VERIFICA que quedo en el registro.
.DESCRIPTION
    Requisitos previos (accion humana; el script los imprime si faltan):
      a) Repositorio publico `micro-calc` creado en hub.docker.com
      b) `docker login -u gthen95` hecho con un Personal Access Token (NO la
         contrasena: los entornos corporativos con SSO suelen rechazarla).

    El script empuja :1.0.0, :latest y :<sha>, y despues DEMUESTRA que la imagen
    esta realmente en el registro (no solo en cache local): borra las copias
    locales y vuelve a hacer pull, comparando los identificadores.
.NOTES
    Plan B si el firewall bloquea registry-1.docker.io: usar ghcr.io con el
    parametro -Registro ghcr. Ver docs/DECISIONES.md (ADR-03).
#>
[CmdletBinding()]
param(
    # Registro destino. Por defecto Docker Hub.
    [ValidateSet("dockerhub", "ghcr")]
    [string]$Registro = "dockerhub",

    # Omite la verificacion destructiva (rmi + pull). Util si hay poca banda.
    [switch]$SinVerificacionProfunda
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\00-config.ps1"

Write-Fase "FASE 4 - PUBLICACION EN DOCKER HUB"

# --- Resolucion del repositorio destino segun el registro -------------------
if ($Registro -eq "ghcr") {
    $repo     = "ghcr.io/" + $Global:DOCKERHUB_USER.ToLower() + "/" + $Global:IMAGE_NAME
    $servidor = "ghcr.io"
    $urlWeb   = "https://github.com/users/$($Global:DOCKERHUB_USER)/packages/container/package/$($Global:IMAGE_NAME)"
} else {
    $repo     = $Global:IMAGE_REPO
    $servidor = "registry-1.docker.io"
    $urlWeb   = "https://hub.docker.com/r/$($Global:IMAGE_REPO)/tags"
}

# =============================================================================
Write-Paso "0. Comprobando sesion en el registro"
# =============================================================================
# OJO: `docker info --format '{{.Username}}'` NO es fiable en este equipo.
# Rancher Desktop configura "credsStore": "wincred" en ~/.docker/config.json, es
# decir, el token se guarda en el Administrador de credenciales de Windows y NO
# en el archivo. En ese modo `docker info` devuelve Username vacio aunque la
# sesion este perfectamente activa. Verificado el 2026-08-21: con Username vacio
# un `docker push` se completo sin problemas.
# Por eso la deteccion es en dos pasos y NUNCA aborta por Username vacio: la
# unica prueba concluyente de que hay sesion es que el push funcione.
$usuario = docker info --format '{{.Username}}' 2>$null

$hayEntradaEnConfig = $false
$rutaConfig = Join-Path $env:USERPROFILE ".docker\config.json"
if (Test-Path $rutaConfig) {
    try {
        $cfg = Get-Content $rutaConfig -Raw | ConvertFrom-Json
        $hayEntradaEnConfig = $null -ne $cfg.auths.'https://index.docker.io/v1/'
        $almacen = $cfg.credsStore
    } catch { }
}

if (-not [string]::IsNullOrWhiteSpace($usuario)) {
    Write-Ok "Sesion iniciada como: $usuario"
    if ($Registro -eq "dockerhub" -and $usuario -ne $Global:DOCKERHUB_USER) {
        Write-Falla "La sesion es de '$usuario' pero la imagen es '$($Global:IMAGE_REPO)'. El push seria rechazado."
        Write-Info "Ejecuta: docker logout ; docker login -u $($Global:DOCKERHUB_USER)"
        exit 1
    }
} elseif ($hayEntradaEnConfig) {
    Write-Ok "Sesion detectada en $rutaConfig (credsStore = '$almacen')"
    Write-Info "El usuario no aparece en 'docker info' porque el token vive en el"
    Write-Info "Administrador de credenciales de Windows, no en config.json. Es normal."
} else {
    Write-Falla "No se detecta ninguna sesion en el registro."
    Write-Host ""
    Write-Host "  REQUISITOS ANTES DE EJECUTAR ESTE SCRIPT:" -ForegroundColor Yellow
    Write-Host "  1) Crear el repositorio PUBLICO micro-calc en:" -ForegroundColor Yellow
    Write-Host "     https://hub.docker.com/repositories" -ForegroundColor Cyan
    Write-Host "  2) Generar un Personal Access Token (permiso Read & Write) en:" -ForegroundColor Yellow
    Write-Host "     https://app.docker.com/settings/personal-access-tokens" -ForegroundColor Cyan
    Write-Host "  3) Iniciar sesion (pega el TOKEN cuando pida Password):" -ForegroundColor Yellow
    Write-Host "     docker login -u $($Global:DOCKERHUB_USER)" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# =============================================================================
Write-Paso "1. Comprobando que la imagen local existe"
# =============================================================================
$SHA = (git rev-parse --short HEAD 2>$null)
if ([string]::IsNullOrWhiteSpace($SHA)) { $SHA = "nogit" }

$tags = @($Global:IMAGE_VERSION, "latest", $SHA)

foreach ($t in $tags) {
    $img = $Global:IMAGE_REPO + ":" + $t
    docker image inspect $img 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Falla "No existe la imagen local '$img'. Ejecuta antes scripts\01-build-local.ps1"
        exit 1
    }
    Write-Ok "Existe localmente: $img"
}

# Si el destino es ghcr, hay que reetiquetar
if ($Registro -eq "ghcr") {
    Write-Paso "1-bis. Reetiquetando para ghcr.io"
    foreach ($t in $tags) {
        docker tag ($Global:IMAGE_REPO + ":" + $t) ($repo + ":" + $t)
        Write-Ok ($repo + ":" + $t)
    }
}

# =============================================================================
Write-Paso "2. docker push (los 3 tags)"
# =============================================================================
Write-Info "Los 3 tags apuntan al MISMO digest, asi que solo el primer push sube"
Write-Info "capas; los otros dos solo registran el nombre. Por eso son instantaneos."
Write-Host ""

foreach ($t in $tags) {
    $img = $repo + ":" + $t
    Write-Host "  > docker push $img" -ForegroundColor DarkCyan
    docker push $img
    if ($LASTEXITCODE -ne 0) {
        Write-Falla "Fallo el push de $img"
        Write-Host ""
        Write-Host "  DIAGNOSTICO:" -ForegroundColor Yellow
        Write-Host "   denied: requested access to the resource is denied" -ForegroundColor Yellow
        Write-Host "      -> el repositorio no existe en hub.docker.com, o el token no tiene Write." -ForegroundColor Yellow
        Write-Host "   unauthorized" -ForegroundColor Yellow
        Write-Host "      -> vuelve a hacer docker login con un token valido." -ForegroundColor Yellow
        Write-Host "   timeout / EOF / connection reset" -ForegroundColor Yellow
        Write-Host "      -> el firewall bloquea $servidor." -ForegroundColor Yellow
        Write-Host "      -> PLAN B: .\scripts\02-push-dockerhub.ps1 -Registro ghcr" -ForegroundColor Yellow
        exit 1
    }
    Write-Ok "Publicado: $img"
    Write-Host ""
}

# =============================================================================
Write-Paso "3. VERIFICACION 1 de 2 - el REGISTRO devuelve el manifest"
# =============================================================================
Write-Info "docker manifest inspect consulta el registro REMOTO, no la cache local."
Write-Host ""

foreach ($t in $tags) {
    $img = $repo + ":" + $t
    $salida = docker manifest inspect $img 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Falla "El registro NO devuelve manifest para $img"
        exit 1
    }
    $coincidencia = [regex]::Match($salida, '"digest"\s*:\s*"(sha256:[a-f0-9]{64})"')
    $primeraCapa = if ($coincidencia.Success) { $coincidencia.Groups[1].Value.Substring(0, 26) + "..." } else { "(n/d)" }
    Write-Ok ("{0,-42} manifest OK   capa1={1}" -f $img, $primeraCapa)
}

$repoDigest = docker image inspect ($repo + ":" + $Global:IMAGE_VERSION) --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' 2>$null
if (-not [string]::IsNullOrWhiteSpace($repoDigest)) {
    Write-Host ""
    Write-Ok "RepoDigest publicado (referencia inmutable por contenido):"
    Write-Host "     $repoDigest" -ForegroundColor Green
    Write-Info "Un tag se puede reasignar; un digest sha256 NO. Es la referencia mas fuerte."
}

# =============================================================================
if ($SinVerificacionProfunda) {
    Write-Info "Se omite la verificacion destructiva (-SinVerificacionProfunda)."
} else {
    Write-Paso "4. VERIFICACION 2 de 2 - borrado local + pull desde el registro"
    # =========================================================================
    Write-Info "Prueba definitiva: si se borra la imagen del disco y el pull la"
    Write-Info "recupera, es que esta REALMENTE en el registro y no en cache local."
    Write-Host ""

    $idAntes = docker image inspect ($repo + ":" + $Global:IMAGE_VERSION) --format '{{.Id}}'
    Write-Info "Image ID antes de borrar : $idAntes"

    # Un contenedor en marcha retiene la imagen: hay que quitarlo primero.
    docker rm -f micro-calc 2>&1 | Out-Null
    foreach ($t in $tags) { docker rmi ($repo + ":" + $t) 2>&1 | Out-Null }

    docker image inspect ($repo + ":" + $Global:IMAGE_VERSION) 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Falla "La imagen sigue en local; la verificacion no seria concluyente."
    } else {
        Write-Ok "Imagen BORRADA del disco local (confirmado)"
    }

    Write-Host ""
    Write-Host "  > docker pull $($repo):$($Global:IMAGE_VERSION)" -ForegroundColor DarkCyan
    docker pull ($repo + ":" + $Global:IMAGE_VERSION)
    if ($LASTEXITCODE -ne 0) {
        Write-Falla "El pull fallo: la imagen NO esta en el registro."
        exit 1
    }

    $idDespues = docker image inspect ($repo + ":" + $Global:IMAGE_VERSION) --format '{{.Id}}'
    Write-Host ""
    Write-Info "Image ID despues del pull: $idDespues"
    if ($idAntes -eq $idDespues) {
        Write-Ok "LOS IDENTIFICADORES COINCIDEN: la imagen descargada es exactamente la publicada."
    } else {
        Write-Falla "Los identificadores NO coinciden. Revisa si hubo un push concurrente."
    }

    # Se recuperan los tags locales auxiliares para las fases siguientes.
    docker tag ($repo + ":" + $Global:IMAGE_VERSION) ($repo + ":latest") 2>&1 | Out-Null
    docker tag ($repo + ":" + $Global:IMAGE_VERSION) ($repo + ":" + $SHA) 2>&1 | Out-Null
    Write-Info "Tags locales :latest y :$SHA restaurados."
}

Write-Host ""
Write-Fase "FASE 4 COMPLETADA"
Write-Ok "Imagen publica: $($repo):$($Global:IMAGE_VERSION)"
Write-Info "Abre en el navegador (EVIDENCIA 11): $urlWeb"
Write-Info "Esa pagina debe mostrar los 3 tags: $($Global:IMAGE_VERSION), latest y $SHA"
