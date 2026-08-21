# certs/ — CA corporativa de inspección TLS

Esta carpeta **debe existir** (el `Dockerfile` la copia siempre), pero su
contenido `*.crt` **está en `.gitignore` y no se publica**.

## ¿Por qué existe?

La red corporativa donde se desarrolló este reto usa un **FortiGate con deep
inspection SSL selectiva**. Verificado el 2026-08-21:

| Host | Emisor del certificado | Estado |
|------|------------------------|--------|
| `repo.maven.apache.org` | `O=Fortinet` | 🔴 interceptado |
| `auth.docker.io` | `O=Fortinet` | 🔴 interceptado |
| `github.com`, `ghcr.io` | `O=Fortinet` | 🔴 interceptado |
| `registry-1.docker.io` | `O=Amazon` | 🟢 limpio |
| `mcr.microsoft.com` | `O=Microsoft Corporation` | 🟢 limpio |
| `registry.k8s.io`, `gcr.io` | `O=Google Trust Services` | 🟢 limpio |

Windows confía en la CA de Fortinet porque TI la instaló en
`LocalMachine\Root`, y Rancher Desktop la propaga a su distro WSL2 — por eso
`docker pull` funciona. Pero el **contenedor de la etapa `build` trae su propio
truststore** (el `cacerts` de la JVM), que no la tiene, y Maven falla con:

```
PKIX path building failed: unable to find valid certification path to requested target
```

## Cómo poblar la carpeta

```powershell
pwsh -File .\scripts\00-extraer-ca-corporativa.ps1
```

El script lee el almacén de certificados de Windows (**sin permisos de
administrador**) y exporta cada CA a un `.crt` en formato PEM.

## Fuera de la red corporativa

No hace falta hacer nada. Si la carpeta no tiene `.crt`, el `Dockerfile` lo
detecta e imprime `[CA] Sin CA corporativa` y usa el truststore por defecto.
El build es portable en ambos escenarios.

## ¿Por qué no se publican los certificados?

Son certificados **públicos** (no contienen clave privada), pero revelan el
número de serie del equipamiento de seguridad de la empresa. Se tratan como
información interna y se regeneran localmente cuando se necesitan.
