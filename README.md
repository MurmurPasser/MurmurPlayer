# Murmur Player

Reproductor de video para iPad (y iPhone) pensado para ver lo que tienes en tu NAS, con Picture in Picture, selección de pistas y decodificación por hardware o software. Se compila en la nube con GitHub Actions: no necesitas una Mac.

## Qué hace (v0.1)

- **NAS por SMB2/3:** busca servidores en tu red (Bonjour), guarda credenciales en el llavero, navega recursos compartidos y carpetas, ordena y busca.
- **Reproduce casi todo:** MKV, MP4, AVI, TS, HEVC 10 bits, HDR10, Dolby Vision, DTS, AC3, FLAC, y subtítulos SRT, ASS y PGS.
- **Motor híbrido:** AVPlayer nativo cuando el formato lo permite y FFmpeg (KSMEPlayer) cuando no. Los archivos del NAS van directo a FFmpeg leyendo `smb://`, sin descargarlos.
- **Hardware o software:** VideoToolbox activado por defecto, con un interruptor para pasar a software.
- **Picture in Picture:** botón en el reproductor y PiP automático al salir de la app.
- **Pistas:** menú de audio y de subtítulos, retardo de subtítulos, velocidad, ajuste o relleno de pantalla, AirPlay.
- **Subtítulos externos:** los `.srt`, `.ass` o `.vtt` que estén junto al video en el NAS se cargan solos.
- **Reanudar:** recuerda dónde te quedaste en cada archivo y tiene una sección «Continuar viendo».
- **Idioma de audio preferido:** elige la pista en español (u otro idioma) automáticamente.
- **Otras fuentes:** archivos de la app Archivos (iCloud, USB, servidores montados), carpeta propia de la app y URLs HTTP, HLS o RTSP.

## Compilar sin Mac (GitHub Actions)

1. Crea un repositorio en GitHub y sube esta carpeta tal cual.
   - Si el repo es **público**, los minutos de macOS son gratis e ilimitados.
   - Si es privado, el plan gratuito da pocos minutos de macOS.
   - KSPlayer es GPL-3.0, así que lo natural es que el repo sea público.
2. Ve a la pestaña **Actions** y abre «Build IPA (sin firmar)». Se ejecuta con cada push a `main`, o a mano con **Run workflow**.
3. El primer build tarda entre 15 y 25 minutos porque descarga FFmpegKit (más de 1 GB). Los siguientes usan caché y son bastante más rápidos.
4. Al terminar, descarga el artefacto `MurmurPlayer-N`. Es un `.zip` que contiene `MurmurPlayer.ipa`.

Si el build falla, los errores de Swift aparecen anotados en el propio resumen del workflow.

## Instalar en el iPad desde Windows

**Opción A: SideStore o AltStore** (se renueva sola)

1. Instala AltServer en tu PC (necesita iTunes e iCloud en sus versiones descargadas de la web de Apple, no las de Microsoft Store).
2. Conecta el iPad por cable e instala AltStore o SideStore con tu Apple ID gratuito.
3. Pasa el `.ipa` al iPad, ábrelo con AltStore o SideStore y pulsa instalar.
4. En el iPad ve a Ajustes › General › VPN y gestión de dispositivos y confía en tu Apple ID.
5. Activa el Modo desarrollador (Ajustes › Privacidad y seguridad) si te lo pide.

Con cuenta gratuita la app caduca cada 7 días. AltStore y SideStore la renuevan automáticamente si el iPad y la PC están en la misma Wi-Fi (o con SideStore, sin PC).

**Opción B: Sideloadly**

Arrastra el `.ipa`, pon tu Apple ID e instala por cable. La renovación cada 7 días es manual.

## Primer uso

1. Abre la app, ve a «Servidores» y pulsa «Añadir servidor».
2. iOS te pedirá permiso de **Red local**: acéptalo, sin él no puede ver el NAS.
3. Elige tu NAS de la lista detectada o escribe su IP.
4. Pon usuario y contraseña y pulsa «Probar conexión». Opcionalmente elige un recurso compartido inicial.
5. Navega hasta el video y tócalo para reproducir.

Si negaste el permiso: Ajustes del iPad › Privacidad y seguridad › Red local › Murmur Player.

### Recomendaciones para el NAS

- Activa **SMB2 o SMB3** (SMB1 no está soportado y además es inseguro).
- Usa un usuario con permiso de solo lectura para la carpeta de video.
- Para remuxes 4K por Wi-Fi, usa el búfer «Máximo» en Ajustes y, si puedes, Wi-Fi de 5 GHz.

## Estructura

```
project.yml                 Especificación XcodeGen (genera el .xcodeproj en CI)
.github/workflows/          Build del .ipa sin firmar
Resources/                  Ícono y color de acento
Sources/App                 Punto de entrada
Sources/Models              Servidor, petición de reproducción, historial, tipos de archivo
Sources/Services            SMB (AMSMB2), Bonjour, llavero, historial, ajustes → KSOptions, router
Sources/Views               Barra lateral, navegador SMB, reproductor, Continuar viendo, local, URL, ajustes
```

Dependencias (Swift Package Manager):

- [KSPlayer](https://github.com/kingslay/KSPlayer), fijado a un commit concreto. Motor AVPlayer + FFmpeg, PiP, interfaz del reproductor.
- [AMSMB2](https://github.com/amosavian/AMSMB2). Cliente SMB2/3 para navegar y descargar subtítulos.

## Límites conocidos de esta versión

- La versión GPL de KSPlayer usa FFmpeg 6.1. Algunas funciones son de su licencia de pago: PiP con subtítulos, AV1 por hardware y ASS con efectos completos.
- iPadOS no cambia la resolución ni la frecuencia de la pantalla según el video (eso solo existe en tvOS). En iPad Pro, ProMotion ajusta la tasa de refresco de forma automática.
- No hay biblioteca con carátulas ni metadatos tipo Infuse. Navega por carpetas.
- No reproduce automáticamente el siguiente episodio.

## Siguientes pasos posibles

- Siguiente episodio automático y listas por carpeta.
- Miniaturas y carátulas (TMDB) con caché local.
- WebDAV, NFS y servidores Jellyfin o Plex.
- Selector de subtítulos por idioma preferido.
- Motor alternativo VLCKit 4 cuando salga estable.

## Licencia

GPL-3.0 (heredada de KSPlayer). AMSMB2 es LGPL-2.1.
