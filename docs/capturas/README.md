# docs/capturas/

Guarda aquí las capturas de pantalla **con estos nombres exactos**. El documento
`docs/evidencias.html` las inserta automáticamente; donde falte una imagen se
muestra un recuadro punteado con instrucciones.

Formato recomendado: **PNG**. Herramienta: **Win+Shift+S** (Recorte de Windows) y
luego *Guardar como* en esta carpeta.

| Archivo | Contenido |
|---------|-----------|
| `01-versiones.png` | Versiones de git, docker, java, kubectl, minikube |
| `02-rancher.png` | Rancher Desktop en Running + Container Engine dockerd |
| `03-fork.png` | Fork en GitHub con la URL visible |
| `04-dockerfile.png` | Dockerfile abierto en VS Code |
| `05-build.png` | `docker build` completo con BUILD SUCCESS |
| `06-images.png` | `docker images` + tamaño real de la imagen |
| `07-run-pruebas.png` | `docker run` y las respuestas JSON |
| `08-navegador-local.png` | Navegador en `http://localhost:8080/suma/7/5` |
| `09-login.png` | `docker login` con Login Succeeded |
| `10-push.png` | `docker push` de los 3 tags + verificación |
| `11-dockerhub.png` | Página de hub.docker.com con los tags |
| `12-k8s-vscode.png` | Carpeta `k8s/` en VS Code |
| `13-minikube-start.png` | `minikube start` y `minikube status` |
| `14-get-nodes.png` | `kubectl get nodes -o wide` |
| `15-apply.png` | `kubectl apply -f k8s/` con los 5 recursos |
| `16-get-all.png` | `kubectl get all -n micro-calc` con Pods Running |
| `17-describe-pod.png` | `kubectl describe pod` con imagen y probes |
| `18-configmap.png` | `kubectl get configmap -o yaml` |
| `19-navegador-k8s.png` | ⭐ Navegador mostrando `gerald-k8s,k8s-minikube` |
| `20-div-cero.png` | `/div/10/0` con el mensaje del ConfigMap |
| `21-logs.png` | `kubectl logs` |
| `22-resiliencia.png` | Borrado de Pod y recreación automática |
| `23-hpa.png` | `kubectl get hpa` con métricas + `kubectl top pods` |
| `24-scale.png` | `kubectl scale` a 4 réplicas |
| `25-endurecimiento.png` | Verificación de no-root, PID 1 y MaxRAMPercentage |
| `26-curl-interno.png` | `curl` desde dentro del clúster |
| `A-fallo-tls.png` | *(opcional)* El fallo `PKIX path building failed` |
| `B-imagepullbackoff.png` | *(opcional)* Pods en `ImagePullBackOff` con el error x509 |

> Esta carpeta está en `.gitignore` salvo este README: las capturas pueden
> contener información del entorno y pesan mucho para un repositorio de código.
