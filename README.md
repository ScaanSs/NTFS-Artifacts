# NTFS Artifacts

**Extracción y análisis de `$LogFile` e `$I30` en un solo comando, listo para Timeline Explorer.**

NTFS Artifacts automatiza dos de las comprobaciones forenses más útiles en una screenshare: el historial de cambios del `$LogFile` y el índice `$I30` de las carpetas, incluido su *slack*, donde quedan rastros de archivos que ya no están. Hace lo mismo que el método manual con FTK Imager, pero sin clics, sin exportar archivos a mano y en una fracción del tiempo.

---

## Ejecución rápida

Abre PowerShell y pega:

```powershell
powershell -command "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; irm 'https://raw.githubusercontent.com/ScaanSs/NTFS-Artifacts/main/NTFS-Artifacts.ps1' | iex"
```

Si no se ha abierto como administrador, el script se vuelve a lanzar solo pidiendo permisos (leer el disco en crudo lo necesita). No instala nada ni modifica el sistema: solo lee del disco.

## Qué hace

Al abrirlo pregunta qué capturar:

```
  Que quieres capturar?

  [1] $LogFile   historial detallado de cambios en archivos (creados, borrados, renombrados)
  [2] $I30       indice de carpetas, con el slack de archivos que ya no estan
  [3] Los dos
```

| Artefacto | Qué muestra | Cómo se obtiene |
|---|---|---|
| **`$LogFile`** | Registro detallado y reciente de lo que ha pasado con los archivos: creaciones, borrados, renombrados, movimientos, escrituras y cambios de fechas, incluidos los *Time Reversal* (fechas movidas hacia atrás, típico de un timestomp). | **go-ntfs** lo extrae del disco → **NTFS Log Tracker** lo convierte a CSV |
| **`$I30`** | Índice de cada carpeta con las fechas de cada archivo (creación, modificación, acceso) y el **slack**: nombres de archivos que estuvieron en la carpeta y ya no están. | **go-ntfs** extrae el stream `$I30` de cada carpeta → `ntfs i30 --csv` lo convierte a CSV |

Al terminar, los resultados se abren automáticamente en **Timeline Explorer** y se abre la carpeta donde se han guardado.

### Resumen de ejecutables

Al final se muestra en pantalla un resumen de todo lo que puede ejecutar código y aparece en los dos artefactos: binarios (`.exe`, `.dll`, `.sys`, `.scr`, `.msi`, `.cpl`, `.ocx`), Java (`.jar`, `.class`), Python (`.py`, `.pyw`, `.pyc`), scripts de Windows (`.bat`, `.cmd`, `.ps1`, `.psm1`, `.vbs`, `.vbe`, `.js`, `.jse`, `.wsf`, `.hta`) y formatos típicos de autoclickers (`.ahk`, `.au3`).

```
  Resumen de ejecutables
  Ext     I30 carpeta   I30 slack     Creados    Borrados     Renomb.     Movidos
  .exe             65          21           -           1           -           -
  .jar             40          16           -           -           -           -
```

Debajo se listan los más relevantes para una SS: los que están en el **slack** (ya no están en la carpeta), los **borrados** y los **renombrados**. Todo se guarda también en `Ejecutables.csv`. Se descarta el ruido conocido, como los archivos temporales que crea PowerShell al arrancar.

### Carpetas analizadas en el `$I30`

Por defecto se analizan las carpetas más relevantes en una SS: Escritorio, Descargas, Documentos, `%TEMP%`, `AppData\Roaming`, `AppData\Local`, `.minecraft`, `.minecraft\mods`, `.minecraft\versions`, `C:\Windows\Prefetch` y la raíz `C:\`. También se pueden elegir carpetas concretas desde el menú.

## Características

- **Sin FTK Imager**: la extracción se hace directamente desde el disco con go-ntfs.
- **Rápido**: las carpetas del `$I30` se procesan en paralelo y, si se eligen los dos artefactos, el `$I30` se saca mientras se parsea el `$LogFile`.
- **Barra de progreso** con porcentaje para cada parte.
- **Horas en UTC** en los dos CSV, para poder compararlos sin confusiones por el horario de verano.
- **Descarga automática** de las herramientas la primera vez (se reutilizan en las siguientes ejecuciones).
- **Sin rastro**: los archivos temporales se borran al terminar; solo se conservan los CSV de resultados.

## Resultados

Se guardan en `Descargas\SSTool\Resultados\NTFS_<fecha>\`:

| Archivo | Contenido |
|---|---|
| `LogFile\NLT_LogFile_<fecha>.csv` | Eventos del `$LogFile` generados por NTFS Log Tracker |
| `I30.csv` | Entradas del `$I30` de todas las carpetas, con la columna `Carpeta` delante. Las entradas en slack aparecen con el nombre marcado como `(slack @ 0x...)` |
| `Ejecutables.csv` | Los ejecutables encontrados en los dos artefactos: origen, evento (en la carpeta, en slack, creado, borrado, renombrado, movido), nombre, ubicación y hora |

## Opciones avanzadas

Descargando el script, se puede ejecutar sin menú:

```powershell
powershell -ExecutionPolicy Bypass -File NTFS-Artifacts.ps1 -Mode Todo
powershell -ExecutionPolicy Bypass -File NTFS-Artifacts.ps1 -Mode I30 -Folders "C:\Users\usuario\Desktop;C:\Juegos"
```

| Parámetro | Descripción |
|---|---|
| `-Mode` | `Todo`, `LogFile` o `I30` (sin él, muestra el menú) |
| `-Drive` | Letra de la unidad a analizar (por defecto, la del sistema) |
| `-Folders` | Carpetas para el `$I30`, separadas por `;` |
| `-NoOpen` | No abrir Timeline Explorer al terminar |
| `-Image` | Analizar una imagen NTFS (`.dd`) en lugar de una unidad |

## Requisitos

- Windows 10 u 11 con PowerShell 5.1 (incluido en Windows).
- Permisos de administrador.
- Conexión a internet la primera vez, para descargar las herramientas.
- [.NET 9 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/9.0) para Timeline Explorer (si falta, el script ofrece instalarlo).

## A tener en cuenta

- El `$LogFile` tiene un tamaño fijo (normalmente 64 MB) y se sobrescribe de forma circular: guarda solo la actividad **más reciente**, desde minutos hasta horas según el uso del disco. Conviene capturarlo lo antes posible al empezar la SS.
- NTFS Log Tracker tarda entre 1 y 3 minutos en procesar un `$LogFile` de 64 MB. Su porcentaje es una estimación, porque el programa no informa de su avance.
- Las carpetas pequeñas no tienen un stream `$I30` independiente (sus entradas están dentro del propio registro de la carpeta); para esas se usa `ntfs stat --i30`, que devuelve las mismas columnas.

## Créditos

- [go-ntfs](https://github.com/Velocidex/go-ntfs) — Velocidex
- [NTFS Log Tracker](https://sites.google.com/site/forensicnote/ntfs-log-tracker) — Junghoon Oh
- [Timeline Explorer](https://ericzimmerman.github.io/) — Eric Zimmerman

Hecho por **Scaan**.
