<#
.SYNOPSIS
    Extrae la(s) CA raiz de inspeccion TLS corporativa del almacen de Windows
    hacia la carpeta certs\ del repositorio, en formato PEM.
.DESCRIPTION
    PROBLEMA QUE RESUELVE
    ---------------------
    La red corporativa usa un FortiGate con "deep inspection" (SSL/TLS
    interception) SELECTIVA. Verificado el 2026-08-21:

        repo.maven.apache.org  -> emisor O=Fortinet   (INTERCEPTADO)
        auth.docker.io         -> emisor O=Fortinet   (INTERCEPTADO)
        github.com / ghcr.io   -> emisor O=Fortinet   (INTERCEPTADO)
        registry-1.docker.io   -> emisor O=Amazon     (limpio)
        mcr.microsoft.com      -> emisor Microsoft    (limpio)
        registry.k8s.io/gcr.io -> Google Trust Svcs   (limpio)

    Windows confia en esa CA porque TI la instalo en LocalMachine\Root, y
    Rancher Desktop la propaga a su distro WSL2 (por eso `docker pull` si
    funciona). Pero el CONTENEDOR de la etapa `build` trae su propio truststore
    (el cacerts de la JVM), que NO la tiene -> Maven falla con:

        PKIX path building failed: unable to find valid certification path

    SOLUCION
    --------
    Exportar la CA a certs\*.crt. El Dockerfile la importa en la etapa `build`
    (en el truststore del SO y en el cacerts de la JVM).

    PRIVACIDAD
    ----------
    La carpeta certs\ esta en .gitignore: estos certificados identifican el
    equipamiento de seguridad de la empresa (numero de serie del FortiGate) y
    NO deben publicarse en un fork publico de GitHub. Son certificados PUBLICOS
    (no contienen clave privada), pero se tratan como informacion interna.
.NOTES
    NO requiere permisos de administrador: solo LEE del almacen de certificados.
#>
[CmdletBinding()]
param(
    # Patron de emisores considerados "de inspeccion corporativa".
    [string]$Patron = 'Fortinet|Zscaler|Netskope|Blue ?Coat|Forcepoint|Palo Alto|McAfee Web Gateway',
    # Host usado para confirmar que la interceptacion existe.
    [string]$HostPrueba = 'repo.maven.apache.org'
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\00-config.ps1"

$destino = Join-Path $Global:REPO_ROOT "certs"

Write-Fase "EXTRACCION DE CA CORPORATIVA DE INSPECCION TLS"

# --- 1. Confirmar empiricamente que hay interceptacion ----------------------
Write-Paso "1. Comprobando el emisor real de https://$HostPrueba"
try {
    $tcp = [Net.Sockets.TcpClient]::new($HostPrueba, 443)
    $ssl = [Net.Security.SslStream]::new($tcp.GetStream(), $false, { $true })
    $ssl.AuthenticateAsClient($HostPrueba)
    $emisor = ([Security.Cryptography.X509Certificates.X509Certificate2]$ssl.RemoteCertificate).Issuer
    $ssl.Dispose(); $tcp.Dispose()
    Write-Info "Emisor: $emisor"
    if ($emisor -match $Patron) {
        Write-Ok "Interceptacion TLS CONFIRMADA. Hay que inyectar la CA en el build."
    } else {
        Write-Ok "Sin interceptacion en esta red. La carpeta certs\ puede quedar vacia."
    }
} catch {
    Write-Falla "No se pudo inspeccionar el certificado: $($_.Exception.Message)"
}

# --- 2. Buscar las CA raiz en el almacen de Windows -------------------------
Write-Paso "2. Buscando CA raiz que coincidan con el patron"
Write-Info "Patron: $Patron"

$encontradas = @()
foreach ($almacen in @("Cert:\LocalMachine\Root", "Cert:\CurrentUser\Root", "Cert:\LocalMachine\CA")) {
    Get-ChildItem $almacen -ErrorAction SilentlyContinue |
        Where-Object { ($_.Subject -match $Patron -or $_.Issuer -match $Patron) -and $_.NotAfter -gt (Get-Date) } |
        ForEach-Object { $encontradas += $_ }
}

# Deduplicar por huella digital (la misma CA suele estar en varios almacenes)
$unicas = $encontradas | Sort-Object Thumbprint -Unique

if ($unicas.Count -eq 0) {
    Write-Ok "No hay CA de inspeccion instaladas. No se necesita hacer nada."
    Write-Info "El Dockerfile detectara la carpeta certs\ vacia y usara el truststore por defecto."
    exit 0
}
Write-Ok "$($unicas.Count) CA unica(s) encontrada(s)"

# --- 3. Exportar a PEM ------------------------------------------------------
Write-Paso "3. Exportando a $destino"

if (-not (Test-Path $destino)) { New-Item -ItemType Directory -Path $destino -Force | Out-Null }
Get-ChildItem $destino -Filter "*.crt" -ErrorAction SilentlyContinue | Remove-Item -Force

$i = 0
foreach ($c in $unicas) {
    $i++
    # Un certificado por archivo: keytool -importcert solo lee el PRIMERO de un
    # PEM concatenado, asi que un bundle unico importaria solo uno.
    $nombre = "corp-ca-{0:D2}-{1}.crt" -f $i, $c.Thumbprint.Substring(0, 8).ToLower()
    $ruta   = Join-Path $destino $nombre
    $b64    = [Convert]::ToBase64String($c.RawData, [Base64FormattingOptions]::InsertLineBreaks)
    $pem    = "-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----`n" -replace "`r`n", "`n"
    [IO.File]::WriteAllText($ruta, $pem, [Text.UTF8Encoding]::new($false))

    $cn = if ($c.Subject -match 'CN=([^,]+)') { $Matches[1] } else { $c.Subject }
    Write-Ok ("{0}  <-  CN={1}  (vence {2:yyyy-MM-dd})" -f $nombre, $cn, $c.NotAfter)
}

Write-Host ""
Write-Fase "EXTRACCION COMPLETADA"
Write-Ok "$i certificado(s) en certs\"
Write-Info "certs\ esta en .gitignore: NO se subiran al fork publico de GitHub."
Write-Info "Siguiente paso: scripts\01-build-local.ps1"
