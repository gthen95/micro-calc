<#
.SYNOPSIS
    FASE 7 - Bateria de pruebas de la aplicacion desplegada en Kubernetes.
.DESCRIPTION
    Prueba la aplicacion por TRES vias distintas, en orden de fiabilidad en
    Windows con driver=docker, y ejecuta las pruebas de resiliencia y escalado.
.NOTES
    SEGURIDAD: todos los kubectl llevan --context minikube EXPLICITO.
#>
[CmdletBinding()]
param(
    [int]$PuertoLocal = 8081,      # 8081 para no chocar con el contenedor local de la FASE 3
    [switch]$SinResiliencia,       # omite el borrado de Pod
    [switch]$SinEscalado           # omite la prueba de escalado
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\00-config.ps1"

$ns   = $Global:K8S_NAMESPACE
$ctx  = $Global:K8S_CONTEXT
$svc  = $Global:K8S_SERVICE
$depl = $Global:K8S_DEPLOYMENT

# Valores que DEBE devolver la aplicacion si la config viene del ConfigMap.
$ESPERADO_RAIZ  = "gerald-k8s,k8s-minikube"
$ESPERADO_ERROR = "Division por cero no permitida (valor desde ConfigMap)"

Write-Fase "FASE 7 - PRUEBAS EN KUBERNETES"
Assert-ContextoMinikube

# =============================================================================
# Funcion auxiliar de prueba HTTP
# =============================================================================
function Test-Endpoint {
    param(
        [string]$BaseUrl,
        [string]$Ruta,
        [string]$Descripcion,
        [string]$Esperado
    )
    Write-Host ""
    Write-Host "  GET $BaseUrl$Ruta" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "      $Descripcion" -ForegroundColor Gray
    if ($Esperado) { Write-Host "      Esperado : $Esperado" -ForegroundColor DarkGray }
    try {
        $r = Invoke-RestMethod -Uri "$BaseUrl$Ruta" -TimeoutSec 10 -ErrorAction Stop
        $txt = if ($r -is [string]) { $r } else { $r | ConvertTo-Json -Compress }
        Write-Host "      RESPUESTA: $txt" -ForegroundColor Green
        if ($Esperado -and ($txt -like "*$Esperado*")) {
            Write-Host "      COINCIDE con lo esperado" -ForegroundColor Green
        }
    } catch {
        Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =============================================================================
Write-Paso "METODO 1 de 3 - kubectl port-forward (el mas fiable en Windows)"
# =============================================================================
# POR QUE ES EL MAS FIABLE AQUI
# -----------------------------
# Con --driver=docker el "nodo" de Kubernetes es un CONTENEDOR que vive dentro
# de la VM WSL2 de Rancher Desktop. Su IP (192.168.49.2) pertenece a una red
# bridge de Docker interna a esa VM, y el host Windows NO tiene ruta hacia ella.
# Por eso http://192.168.49.2:30080 suele dar timeout desde el navegador de
# Windows aunque el NodePort este perfectamente configurado.
#
# port-forward no depende de esa ruta: abre un tunel sobre la conexion HTTPS que
# kubectl YA tiene con el API server (que si esta publicado en 127.0.0.1 por
# Minikube) y el API server reenvia al Pod. Funciona siempre que kubectl
# funcione, sin importar la topologia de red intermedia.
Write-Info "Abriendo tunel: localhost:$PuertoLocal -> svc/$svc:80 -> Pod:8080"

$base = "http://localhost:$PuertoLocal"

# -----------------------------------------------------------------------------
# El tunel se abre desde una funcion porque hay que RECREARLO despues de la
# prueba de resiliencia. Motivo, y es un detalle importante:
# `kubectl port-forward svc/<nombre>` NO balancea. Resuelve el Service una sola
# vez, elige UN Pod concreto y mantiene el tunel contra ese Pod. Si ese Pod
# desaparece -que es justo lo que provoca la prueba de resiliencia- el tunel
# muere con el, aunque el Service siga sirviendo perfectamente desde la otra
# replica. Es una limitacion de la herramienta de depuracion, NO un fallo de la
# aplicacion ni del Service.
# -----------------------------------------------------------------------------
# Libera el puerto local antes de abrir un tunel nuevo.
# Detalle observado en la practica: cuando el Pod al que estaba enganchado el
# port-forward desaparece, kubectl imprime el error pero NO siempre termina el
# proceso. El proceso zombi sigue reteniendo el puerto y el tunel nuevo no puede
# hacer bind. Por eso no basta con Stop-Process: hay que esperar a que el puerto
# quede realmente libre.
function Stop-Tunel {
    param($Proceso)
    if ($Proceso -and -not $Proceso.HasExited) {
        Stop-Process -Id $Proceso.Id -Force -ErrorAction SilentlyContinue
    }
    # Por si quedara algun kubectl port-forward huerfano sobre este puerto.
    for ($i = 1; $i -le 20; $i++) {
        $enUso = Get-NetTCPConnection -LocalPort $PuertoLocal -State Listen -ErrorAction SilentlyContinue
        if (-not $enUso) { return $true }
        foreach ($c in $enUso) {
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Start-Tunel {
    Stop-Tunel -Proceso $null | Out-Null   # asegura que el puerto esta libre
    $proc = Start-Process -FilePath "kubectl" `
        -ArgumentList "--context", $ctx, "port-forward", "-n", $ns, "svc/$svc", "$($PuertoLocal):80" `
        -PassThru -WindowStyle Hidden
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Milliseconds 700
        try {
            Invoke-RestMethod -Uri "$base/" -TimeoutSec 3 -ErrorAction Stop | Out-Null
            return @{ Proceso = $proc; Ok = $true; Intentos = $i }
        } catch { }
    }
    return @{ Proceso = $proc; Ok = $false; Intentos = 30 }
}

$tunel = Start-Tunel
$pf    = $tunel.Proceso
$listo = $tunel.Ok
if ($listo) { Write-Ok "Tunel operativo tras $($tunel.Intentos) intento(s)" }

if (-not $listo) {
    Write-Falla "El port-forward no respondio. Se continua con los otros metodos."
} else {
    Write-Host ""
    Write-Host "  ###############################################################" -ForegroundColor Magenta
    Write-Host "  #   PRUEBAS FUNCIONALES SOBRE EL SERVICIO DE KUBERNETES       #" -ForegroundColor Magenta
    Write-Host "  ###############################################################" -ForegroundColor Magenta

    Test-Endpoint $base "/" `
        "EVIDENCIA ESTRELLA: los valores salen del ConfigMap, no de la imagen" $ESPERADO_RAIZ
    Test-Endpoint $base "/suma/7/5"   "Suma 7 + 5"      "12"
    Test-Endpoint $base "/resta/10/3" "Resta 10 - 3"    "7"
    Test-Endpoint $base "/div/10/2"   "Division 10 / 2" "5"
    Test-Endpoint $base "/div/10/0" `
        "SEGUNDA EVIDENCIA: el mensaje de error viene del ConfigMap" $ESPERADO_ERROR

    Write-Host ""
    Write-Info "Comparativa de la MISMA aplicacion segun el origen de la configuracion:"
    Write-Host "     application.properties (dentro del JAR) : admin,localhost" -ForegroundColor DarkGray
    Write-Host "     docker run -e ...        (FASE 3)       : gerald,docker-local" -ForegroundColor DarkGray
    Write-Host "     ConfigMap de Kubernetes  (FASE 7)       : $ESPERADO_RAIZ" -ForegroundColor Green
}

# =============================================================================
Write-Paso "METODO 2 de 3 - minikube service --url"
# =============================================================================
Write-Info "Devuelve la URL del NodePort. En Windows con driver=docker, minikube"
Write-Info "crea ademas un tunel propio, por eso a veces si responde. Si da"
Write-Info "timeout NO es un fallo de la aplicacion, sino de la ruta de red."
$urlNodePort = (minikube service $svc -n $ns --url 2>$null | Select-Object -First 1)
if ($urlNodePort) {
    Write-Ok "URL del NodePort: $urlNodePort"
    try {
        $r = Invoke-RestMethod -Uri "$urlNodePort/suma/20/22" -TimeoutSec 8 -ErrorAction Stop
        Write-Host "      GET $urlNodePort/suma/20/22" -ForegroundColor White
        Write-Host "      RESPUESTA: $($r | ConvertTo-Json -Compress)" -ForegroundColor Green
    } catch {
        Write-Info "No respondio: $($_.Exception.Message)"
        Write-Info "Comportamiento esperado en Windows. Se usa el METODO 1."
    }
}
$ipNodo = (minikube ip 2>$null)
Write-Info "IP del nodo: $ipNodo  ->  NodePort directo seria http://$ipNodo`:30080"

# =============================================================================
Write-Paso "METODO 3 de 3 - curl DESDE DENTRO del clúster"
# =============================================================================
# Este metodo elimina por completo la red del host de la ecuacion: un Pod
# efimero resuelve el nombre DNS del Service y llama al ClusterIP. Si esto
# funciona, el Service y los Pods estan bien aunque el host no los alcance.
Write-Info "Se lanza un Pod efimero que resuelve micro-calc.micro-calc.svc.cluster.local"
kubectl --context $ctx run tester-$(Get-Random -Maximum 9999) `
    --rm -i --restart=Never --image=curlimages/curl:8.11.1 -n $ns -- `
    -s "http://$svc.$ns.svc.cluster.local/suma/2/3"
Write-Host ""

# =============================================================================
Write-Paso "kubectl logs (de todos los Pods de la aplicacion)"
# =============================================================================
kubectl --context $ctx logs -n $ns -l app.kubernetes.io/name=micro-calc --tail=20 --prefix

# =============================================================================
Write-Paso "kubectl describe pod (imagen, probes y Events)"
# =============================================================================
$pod = kubectl --context $ctx get pods -n $ns -o jsonpath='{.items[0].metadata.name}'
Write-Info "Pod inspeccionado: $pod"
Write-Host ""
kubectl --context $ctx describe pod $pod -n $ns

# =============================================================================
Write-Paso "Estado del HPA"
# =============================================================================
# El HPA muestra TARGETS = <unknown>/70% hasta que metrics-server entrega su
# primera muestra. En las pruebas de este equipo tardo poco mas de un minuto
# desde que se habilito el addon. En vez de fotografiar un <unknown> que parece
# un error, se espera activamente hasta 3 minutos a que aparezca la metrica.
Write-Info "Esperando a que metrics-server publique la primera muestra..."
$conMetrica = $false
for ($i = 1; $i -le 36; $i++) {
    $t = kubectl --context $ctx get hpa $depl -n $ns -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($t)) { $conMetrica = $true; break }
    Start-Sleep -Seconds 5
}
Write-Host ""
kubectl --context $ctx get hpa -n $ns
Write-Host ""
if ($conMetrica) {
    Write-Ok "HPA con metricas reales. Ya NO muestra <unknown>."
    Write-Info "El objetivo es 70% del REQUEST de CPU (200m), es decir 140m por Pod."
} else {
    Write-Falla "Sigue en <unknown> tras 3 minutos. Comprueba el addon:"
    Write-Info "  minikube addons enable metrics-server"
    Write-Info "  kubectl --context $ctx get pods -n kube-system -l k8s-app=metrics-server"
}

Write-Host ""
Write-Info "Consumo real de cada Pod (kubectl top):"
kubectl --context $ctx top pods -n $ns 2>&1 | Out-String | Write-Host
Write-Info "Comparar con los limits del Deployment: cpu 500m / memory 512Mi."

# =============================================================================
if (-not $SinResiliencia) {
    Write-Paso "PRUEBA DE RESILIENCIA - borrar un Pod y ver como se recrea"
    # =========================================================================
    # Quien recrea el Pod es el ReplicaSet, no el Deployment: el Deployment
    # gestiona ReplicaSets, y el ReplicaSet vigila que el numero de Pods con sus
    # labels coincida con `replicas`. Al borrar uno, el bucle de reconciliacion
    # detecta 1 != 2 y crea uno nuevo en segundos.
    Write-Host "  ANTES:" -ForegroundColor Yellow
    kubectl --context $ctx get pods -n $ns -o wide

    $victima = kubectl --context $ctx get pods -n $ns -o jsonpath='{.items[0].metadata.name}'
    Write-Host ""
    Write-Host "  > kubectl delete pod $victima -n $ns" -ForegroundColor DarkCyan
    kubectl --context $ctx delete pod $victima -n $ns

    Write-Host ""
    Write-Host "  INMEDIATAMENTE DESPUES (se ve el Pod nuevo en ContainerCreating):" -ForegroundColor Yellow
    kubectl --context $ctx get pods -n $ns -o wide

    Write-Info "Esperando a que el nuevo Pod este Ready..."
    kubectl --context $ctx wait --for=condition=Ready pod -l app.kubernetes.io/name=micro-calc -n $ns --timeout=180s | Out-Null

    Write-Host ""
    Write-Host "  DESPUES (2/2 de nuevo, con AGE distinto: uno es nuevo):" -ForegroundColor Yellow
    kubectl --context $ctx get pods -n $ns -o wide
    Write-Ok "El ReplicaSet restauro el estado deseado automaticamente"

    # -------------------------------------------------------------------------
    # El tunel de port-forward apuntaba a UN Pod concreto. Si la victima fue ese
    # Pod, el tunel murio con el y hay que reabrirlo. El Service, en cambio,
    # nunca dejo de servir: la otra replica siguio en los Endpoints todo el
    # tiempo. Se demuestra reabriendo el tunel y volviendo a llamar.
    # -------------------------------------------------------------------------
    if ($listo) {
        Write-Host ""
        Write-Info "El tunel de port-forward estaba enganchado al Pod borrado, asi que"
        Write-Info "murio con el. NO es un fallo del Service: port-forward elige un Pod"
        Write-Info "fijo y no balancea. Se reabre el tunel para comprobar el servicio."
        Stop-Tunel -Proceso $pf | Out-Null
        $tunel = Start-Tunel
        $pf    = $tunel.Proceso
        if ($tunel.Ok) {
            Write-Ok "Tunel reabierto contra una replica sana"
            Test-Endpoint $base "/suma/1/1" "El Service sigue sirviendo tras perder un Pod" "2"
            Test-Endpoint $base "/" "La configuracion del ConfigMap se mantiene en el Pod nuevo" $ESPERADO_RAIZ
        } else {
            Write-Falla "No se pudo reabrir el tunel."
        }
    }
}

# =============================================================================
if (-not $SinEscalado) {
    Write-Paso "PRUEBA DE ESCALADO - 2 -> 4 -> 2 replicas"
    # =========================================================================
    Write-Host "  > kubectl scale deployment $depl --replicas=4 -n $ns" -ForegroundColor DarkCyan
    kubectl --context $ctx scale deployment $depl --replicas=4 -n $ns
    kubectl --context $ctx rollout status deployment/$depl -n $ns --timeout=180s
    Write-Host ""
    kubectl --context $ctx get pods -n $ns -o wide
    Write-Ok "Escalado a 4 replicas"

    Write-Host ""
    Write-Info "El Service reparte entre las 4: sus Endpoints ahora son 4 IP."
    kubectl --context $ctx get endpointslices -n $ns -o wide

    Write-Host ""
    Write-Host "  > kubectl scale deployment $depl --replicas=2 -n $ns" -ForegroundColor DarkCyan
    kubectl --context $ctx scale deployment $depl --replicas=2 -n $ns
    kubectl --context $ctx rollout status deployment/$depl -n $ns --timeout=180s
    Write-Host ""
    kubectl --context $ctx get pods -n $ns -o wide
    Write-Ok "Vuelta a 2 replicas (el minimo que exige el HPA)"
}

# =============================================================================
Write-Paso "Cerrando el tunel de port-forward"
# =============================================================================
if (Stop-Tunel -Proceso $pf) {
    Write-Ok "Tunel cerrado y puerto $PuertoLocal liberado"
} else {
    Write-Falla "El puerto $PuertoLocal sigue ocupado. Cierra el proceso a mano:"
    Write-Info "  Get-NetTCPConnection -LocalPort $PuertoLocal -State Listen"
}

Write-Host ""
Write-Fase "FASE 7 COMPLETADA"
Write-Info "Para la captura en NAVEGADOR (EVIDENCIA 19), deja el tunel abierto en"
Write-Info "una terminal aparte y abre http://localhost:$PuertoLocal/"
Write-Host ""
Write-Host "  kubectl --context minikube port-forward -n $ns svc/$svc $($PuertoLocal):80" -ForegroundColor Cyan
