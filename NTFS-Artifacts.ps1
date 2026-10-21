<#
    NTFS Artifacts - SSTool (Scaan)

    Saca el $LogFile y/o el $I30 de las carpetas habituales directamente del disco
    (sin FTK Imager), los pasa a CSV y los abre en Timeline Explorer.

      $LogFile : go-ntfs lo extrae (como FTK Imager)  ->  NTFS Log Tracker lo pasa a CSV
      $I30     : go-ntfs lo extrae de cada carpeta (como FTK Imager)  ->  ntfs i30 --csv
                 (incluido el slack, donde quedan nombres de archivos borrados)

    Uso:
      powershell -command "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; irm 'https://raw.githubusercontent.com/ScaanSs/NTFS-Artifacts/main/NTFS-Artifacts.ps1' | iex"
      powershell -ExecutionPolicy Bypass -File NTFS-Artifacts.ps1
      powershell -ExecutionPolicy Bypass -File NTFS-Artifacts.ps1 -Mode LogFile
      powershell -ExecutionPolicy Bypass -File NTFS-Artifacts.ps1 -Mode I30 -Folders "C:\Users\x\Desktop;C:\Juegos"

    -Mode    Todo | LogFile | I30   (sin -Mode muestra un menu)
    -Drive   Letra de la unidad (por defecto la del sistema)
    -Folders Carpetas para el $I30 separadas por ';' (por defecto las habituales)
    -Image   Analizar una imagen NTFS (.dd) en vez de una unidad (para pruebas)
    -NoOpen  No abrir Timeline Explorer al terminar
#>
param(
    [ValidateSet('', 'Todo', 'LogFile', 'I30')] [string]$Mode = '',
    [string]$Drive = $env:SystemDrive.TrimEnd(':'),
    [string]$Folders = '',
    [string]$Image = '',
    [switch]$NoOpen
)

# Donde esta publicado el script: con "irm | iex" no hay archivo local, y para reabrirlo como
# administrador se vuelve a descargar de aqui.
$ScriptUrl = 'https://raw.githubusercontent.com/ScaanSs/NTFS-Artifacts/main/NTFS-Artifacts.ps1'

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest es mucho mas rapido sin barra de progreso
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Info($msg)  { Write-Host " > $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host " + $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host " ! $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host " x $msg" -ForegroundColor Red }

# Los programas se lanzan con Process de .NET, no con "&" ni Start-Process: en algunos PCs la variable
# PATHEXT esta modificada (sin .EXE) y PowerShell se niega a ejecutar cualquier .exe ("Cannot run a
# document in the middle of a pipeline"). En texto para poder cargarlo tambien en los runspaces del $I30.
$ExeHelpers = @'
function Join-Args([string[]]$list) {
    $q = foreach ($a in $list) {
        if ($a -eq '') { '""' }
        elseif ($a -notmatch '[\s"]') { $a }
        else { '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    }
    return ($q -join ' ')
}
# Ejecuta un programa, espera a que termine y devuelve su salida (UTF-8) en lineas. $LastExit = codigo de salida.
function Invoke-Exe([string]$exe, [string[]]$argList) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, (Join-Args $argList)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $null = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $script:LastExit = $p.ExitCode
    return @($out -split "`r?`n" | Where-Object { $_ -ne '' })
}
# Lanza un programa sin esperar (ventanas o trabajo en segundo plano) y devuelve el proceso.
function Start-Exe([string]$exe, [string[]]$argList, [switch]$Hidden) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, (Join-Args $argList)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = [bool]$Hidden
    $psi.WorkingDirectory = Split-Path $exe
    return [Diagnostics.Process]::Start($psi)
}
'@
. ([scriptblock]::Create($ExeHelpers))

Write-Host ""
Write-Host "  NTFS Artifacts  -  `$LogFile + `$I30  ->  Timeline Explorer" -ForegroundColor Blue
Write-Host "  SSTool - Scaan" -ForegroundColor DarkGray
Write-Host ""

# ---------- Administrador (leer el disco en crudo lo necesita) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Image) {
    if ($PSCommandPath) {
        # Ejecutado como archivo: reabrir ese archivo como administrador.
        Warn "Hace falta administrador; reabriendo con permisos..."
        $relaunch = @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Drive', $Drive)
        if ($Mode)    { $relaunch += @('-Mode', $Mode) }
        if ($Folders) { $relaunch += @('-Folders', "`"$Folders`"") }
        if ($NoOpen)  { $relaunch += '-NoOpen' }
        Start-Process (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList $relaunch
    }
    elseif ($ScriptUrl -like 'https://*') {
        # Ejecutado con "irm | iex": no hay archivo, asi que se vuelve a descargar como administrador.
        Warn "Hace falta administrador; reabriendo con permisos..."
        $cmd = "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; irm '$ScriptUrl' | iex"
        Start-Process (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList '-NoExit', '-Command', $cmd
    }
    else { Fail "Ejecuta PowerShell como administrador y vuelve a lanzar el script." }
    return
}

# ---------- Menu ----------
# Pregunta hasta que la respuesta sea una de las opciones validas.
function Ask($prompt, $valid) {
    while ($true) {
        $a = (Read-Host "  $prompt").Trim()
        if ($valid -contains $a) { return $a }
        Warn "Opcion no valida, escribe $($valid -join ', ')."
    }
}

if (-not $Mode) {
    Write-Host "  Que quieres capturar?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] `$LogFile   historial detallado de cambios en archivos (creados, borrados, renombrados)"
    Write-Host "  [2] `$I30       indice de carpetas, con el slack de archivos que ya no estan"
    Write-Host "  [3] Los dos"
    Write-Host ""
    switch (Ask "Elige 1, 2 o 3" @('1', '2', '3')) {
        '1' { $Mode = 'LogFile' }
        '2' { $Mode = 'I30' }
        '3' { $Mode = 'Todo' }
    }
    Write-Host ""
}

# Si toca $I30 y no se pasaron carpetas, preguntar cuales.
if ($Mode -in 'Todo', 'I30' -and -not $Folders -and -not $Image -and -not $PSBoundParameters.ContainsKey('Mode')) {
    Write-Host "  De que carpetas sacar el `$I30?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Las habituales (Escritorio, Descargas, Documentos, Temp, AppData, .minecraft, Prefetch, C:\)"
    Write-Host "  [2] Elegirlas yo"
    Write-Host ""
    if ((Ask "Elige 1 o 2" @('1', '2')) -eq '2') {
        Write-Host ""
        Write-Host "  Escribe las carpetas separadas por ';'  (ej: C:\Users\yo\Desktop;C:\Juegos)" -ForegroundColor DarkGray
        while (-not $Folders) { $Folders = (Read-Host "  Carpetas").Trim() }
    }
    Write-Host ""
}
$doLog = $Mode -in 'Todo', 'LogFile'
$doI30 = $Mode -in 'Todo', 'I30'

# ---------- Carpetas ----------
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$OutDir  = Join-Path $env:USERPROFILE "Downloads\SSTool\Resultados\NTFS_$stamp"
$ToolDir = Join-Path $env:LOCALAPPDATA 'SSTool\tools'   # se reutilizan entre ejecuciones
$WorkDir = Join-Path $env:TEMP "SSTool-ntfs-$stamp"     # $LogFile en crudo; se borra al final
New-Item -ItemType Directory -Force -Path $OutDir, $ToolDir, $WorkDir | Out-Null

$Volume = if ($Image) { $Image } else { "\\.\$($Drive):" }

# ---------- Herramientas ----------
# Un .exe de verdad empieza por "MZ". Una descarga cortada, una pagina de error o un archivo vaciado
# por el antivirus no, y al ejecutarlo fallaria de forma rara: se detecta antes y se vuelve a bajar.
function Test-Exe([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    if ((Get-Item -LiteralPath $path).Length -lt 10KB) { return $false }
    try {
        $fs = [IO.File]::OpenRead($path)
        try { return ($fs.ReadByte() -eq 0x4D -and $fs.ReadByte() -eq 0x5A) } finally { $fs.Close() }
    }
    catch { return $false }
}

function Get-Zip($url, $name, $exeName) {
    $dir = Join-Path $ToolDir $name
    $exe = Get-ChildItem $dir -Recurse -Filter $exeName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe -and (Test-Exe $exe.FullName)) { return $exe.FullName }
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    Info "Descargando $name..."
    $zip = Join-Path $WorkDir "$name.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    $exe = Get-ChildItem $dir -Recurse -Filter $exeName | Select-Object -First 1
    if (-not $exe) { throw "No se encontro $exeName dentro de $name." }
    if (-not (Test-Exe $exe.FullName)) { throw "$exeName no es un ejecutable valido (puede que el antivirus lo haya bloqueado)." }
    return $exe.FullName
}

function Get-Ntfs {
    $exe = Join-Path $ToolDir 'go-ntfs\ntfs.exe'
    if (Test-Exe $exe) { return $exe }
    Info "Descargando go-ntfs..."
    New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null
    Invoke-WebRequest -Uri 'https://github.com/Velocidex/go-ntfs/releases/download/v0.2.0/ntfs-windows-amd64.exe' -OutFile $exe -UseBasicParsing
    if (-not (Test-Exe $exe)) { throw "ntfs.exe no es un ejecutable valido (puede que el antivirus lo haya bloqueado)." }
    return $exe
}

# Timeline Explorer (net9) necesita el .NET 9 Desktop Runtime.
function Test-DesktopRuntime {
    $base = Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.WindowsDesktop.App'
    return [bool](Get-ChildItem $base -Directory -Filter '9.*' -ErrorAction SilentlyContinue)
}

try {
    $ntfs = Get-Ntfs
    $nlt  = if ($doLog) { Get-Zip 'https://github.com/AguaConGas17/Screenshare/raw/refs/heads/main/NTFS_Log_Tracker_CMDv1.9.zip' 'NTFSLogTracker' 'NTFS_Log_Tracker_CMD.exe' }
    $tle  = if (-not $NoOpen) { Get-Zip 'https://download.ericzimmermanstools.com/net9/TimelineExplorer.zip' 'TimelineExplorer' 'TimelineExplorer.exe' }
}
catch { Fail "No se pudieron descargar las herramientas: $($_.Exception.Message)"; return }

$results = @()
$nltProc = $null

# ---------- $LogFile: go-ntfs lo extrae (lo que se hacia con FTK Imager) ----------
if ($doLog) {
    Info "Extrayendo `$LogFile de $Volume..."
    $raw = Join-Path $WorkDir '$LogFile'
    # MFT 2 = $LogFile
    $null = Invoke-Exe $ntfs @('cat', '--out', $raw, $Volume, '2')
    if ($LastExit -ne 0 -or -not (Test-Path -LiteralPath $raw) -or (Get-Item -LiteralPath $raw).Length -eq 0) {
        Fail "No se pudo extraer el `$LogFile."
    }
    else {
        $rawMB = (Get-Item -LiteralPath $raw).Length / 1MB
        Ok ("`$LogFile extraido ({0:N1} MB)" -f $rawMB)
        $logOut = Join-Path $OutDir 'LogFile'
        New-Item -ItemType Directory -Force -Path $logOut | Out-Null
        # NTFS Log Tracker (el de la guia, version de consola) lo pasa a CSV. Es lo lento: va en
        # segundo plano con prioridad alta y, mientras, se saca el $I30. -t 0 = horas en UTC, como go-ntfs.
        $nltProc = Start-Exe $nlt @('-l', $raw, '-o', $logOut, '-c', '-t', '0') -Hidden
        try { $nltProc.PriorityClass = 'High' } catch { }
        $nltStart = Get-Date
        Info "NTFS Log Tracker esta parseando el `$LogFile en segundo plano..."
    }
}

# Espera a NTFS Log Tracker con una barra de % y recoge su CSV.
# NLT no informa de su avance (lee el archivo de golpe y luego solo calcula), asi que el % es una
# estimacion. Lo que tarda varia mucho segun el contenido (medido 1-2,5 s por MB), por eso la barra
# se va frenando (99 * (1 - e^-t/tau)): siempre se mueve, nunca llega a 100% antes de terminar.
function Complete-LogFile {
    $tau = [Math]::Max(5, $rawMB * 1.0)
    while (-not $nltProc.HasExited) {
        $e = (Get-Date) - $nltStart
        $pct = [int](99 * (1 - [Math]::Exp(-$e.TotalSeconds / $tau)))
        $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
        Write-Host ("`r > Parseando `$LogFile  [{0}] ~{1,2}%  {2:mm\:ss}  " -f $bar, $pct, $e) -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 500
    }
    $e = (Get-Date) - $nltStart
    Write-Host ("`r > Parseando `$LogFile  [{0}] 100%  {1:mm\:ss}  " -f ('#' * 20), $e) -ForegroundColor Cyan
    $csv = Get-ChildItem $logOut -Filter 'NLT_LogFile*.csv' -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 1
    if (-not $csv) { Fail "NTFS Log Tracker no genero el CSV."; return }
    # NLT tambien deja un CSV de $UsnJrnl vacio (no le pasamos el journal) y su base SQLite.
    Get-ChildItem $logOut -Filter 'NLT_UsnJrnl*.csv' | Where-Object { $_.Length -lt 1KB } | Remove-Item -Force
    $rows = 0
    $reader = New-Object IO.StreamReader $csv.FullName
    while ($null -ne $reader.ReadLine()) { $rows++ }
    $reader.Close()
    Ok ("`$LogFile -> {0}  ({1:N0} eventos, {2:mm\:ss})" -f $csv.Name, ($rows - 1), $e)
    $script:results += $csv.FullName
    $script:logCsv = $csv.FullName
}

# ---------- $I30: go-ntfs lo extrae y lo parsea ----------
function Get-DefaultFolders {
    $list = @(
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        [Environment]::GetFolderPath('MyDocuments'),
        $env:TEMP,
        $env:APPDATA,
        $env:LOCALAPPDATA,
        (Join-Path $env:APPDATA '.minecraft'),
        (Join-Path $env:APPDATA '.minecraft\mods'),
        (Join-Path $env:APPDATA '.minecraft\versions'),
        (Join-Path $env:SystemRoot 'Prefetch'),
        "$($Drive):\"
    )
    return $list | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
}

# Una carpeta, como en la guia: stat localiza el stream $I30, cat lo extrae (lo que se hacia con
# FTK Imager) e "i30 --csv" lo pasa a CSV. Las carpetas pequenas no tienen stream $I30 propio (sus
# entradas van dentro del registro, en $INDEX_ROOT) y FTK tampoco lo puede exportar: para esas se
# usa "stat --i30" de go-ntfs, con las mismas columnas que i30 --csv.
# Corre en un runspace aparte; $prog[$key] marca cuantos de los 3 pasos lleva.
$I30Job = {
    param($ntfs, $Volume, $rel, $work, $prog, $key, $helpers)
    . ([scriptblock]::Create($helpers))   # Invoke-Exe en este runspace
    $r = @{ Rows = @(); Fallback = $false; Error = $null }
    $json = Invoke-Exe $ntfs @('stat', $Volume, $rel)
    $prog[$key] = 1
    if (-not $json) { $r.Error = 'no se pudo leer la carpeta'; $prog[$key] = 3; return $r }
    $alloc = (($json -join "`n") | ConvertFrom-Json).Attributes |
        Where-Object { $_.TypeId -eq 160 -and $_.Name -eq '$I30' } | Select-Object -First 1
    if ($alloc) {
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        $raw = Join-Path $work '$I30'
        $null = Invoke-Exe $ntfs @('cat', '--out', $raw, $Volume, $alloc.Inode)
        $prog[$key] = 2
        $csv = Invoke-Exe $ntfs @('i30', '--csv', $raw)
        $prog[$key] = 3
        if ($csv) { $r.Rows = @($csv | ConvertFrom-Csv) } else { $r.Error = 'i30 no devolvio nada' }
        return $r
    }
    $out = @(Invoke-Exe $ntfs @('stat', '--i30', $Volume, $rel))
    $prog[$key] = 3
    $r.Fallback = $true
    # stat --i30 imprime dos JSON seguidos: la carpeta ({...}) y la lista del $I30 ([...]).
    for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i] -match '^\[') { break } }
    if ($i -ge $out.Count) { return $r }
    # Mismo formato que i30 --csv: "2023-06-23 02:16:17.9724723 +0000 UTC" y "(slack @ 0x..)" en el nombre.
    $fmt = { param($t) if ($t) { ($t -replace 'T', ' ') -replace 'Z$', ' +0000 UTC' } }
    foreach ($e in (($out[$i..($out.Count - 1)] -join "`n") | ConvertFrom-Json)) {
        $name = if ($e.IsSlack) { "$($e.Name) (slack @ 0x{0:x})" -f [int64]$e.SlackOffset } else { $e.Name }
        $r.Rows += [pscustomobject]@{ Name = $name; NameType = $e.NameType; Size = $e.Size; AllocatedSize = $e.AllocatedSize
                                      Mtime = (& $fmt $e.Mtime); Atime = (& $fmt $e.Atime); Ctime = (& $fmt $e.Ctime); Btime = (& $fmt $e.Btime) }
    }
    return $r
}

if ($doI30) {
    if ($Image) {
        # Imagen de prueba: rutas relativas a su raiz ("5" = raiz).
        $targets = if ($Folders) { $Folders -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { @('5') }
    }
    elseif ($Folders) {
        $targets = $Folders -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }
    }
    else { $targets = Get-DefaultFolders }

    # go-ntfs quiere la ruta sin la letra de unidad; la raiz es la entrada 5 de la MFT.
    $jobs = @()
    foreach ($folder in $targets) {
        if ($Image) { $rel = $folder }
        else {
            $full = $folder.TrimEnd('\')
            if ($full -notmatch '^[A-Za-z]:') { Warn "Ruta no valida: $folder"; continue }
            if ($full.Substring(0, 1).ToUpper() -ne $Drive.ToUpper()) { Warn "Esta en otra unidad, se omite: $folder"; continue }
            $rel = $full.Substring(2).TrimStart('\')
            if (-not $rel) { $rel = '5' }
        }
        $jobs += [pscustomobject]@{ Folder = $folder; Rel = $rel; Key = "j$($jobs.Count)" }
    }

    # Todas las carpetas a la vez (hasta 8), con la barra de % segun los pasos terminados.
    $prog = [hashtable]::Synchronized(@{})
    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Max(1, [Math]::Min(8, $jobs.Count)))
    $pool.Open()
    foreach ($j in $jobs) {
        $prog[$j.Key] = 0
        $ps = [powershell]::Create().AddScript($I30Job).AddArgument($ntfs).AddArgument($Volume).AddArgument($j.Rel).
            AddArgument((Join-Path $WorkDir $j.Key)).AddArgument($prog).AddArgument($j.Key).AddArgument($ExeHelpers)
        $ps.RunspacePool = $pool
        $j | Add-Member Ps $ps
        $j | Add-Member Handle $ps.BeginInvoke()
    }
    $totalSteps = [Math]::Max(1, $jobs.Count * 3)
    do {
        $doneSteps = 0; foreach ($v in @($prog.Values)) { $doneSteps += $v }
        $ready = @($jobs | Where-Object { $_.Handle.IsCompleted }).Count
        $pct = [int](100 * $doneSteps / $totalSteps)
        $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
        Write-Host ("`r > Sacando `$I30  [{0}] {1,3}%  ({2}/{3} carpetas)  " -f $bar, $pct, $ready, $jobs.Count) -NoNewline -ForegroundColor Cyan
        if ($ready -lt $jobs.Count) { Start-Sleep -Milliseconds 150 }
    } while ($ready -lt $jobs.Count)
    Write-Host ""

    # Salida tal cual de go-ntfs (Name, NameType, Size, AllocatedSize, Mtime, Atime, Ctime, Btime),
    # con la carpeta delante para juntarlas todas en un CSV.
    $rowsI30 = New-Object System.Collections.Generic.List[object]
    foreach ($j in $jobs) {
        $r = $j.Ps.EndInvoke($j.Handle) | Select-Object -Last 1
        $j.Ps.Dispose()
        if (-not $r -or $r.Error) { Warn "No se pudo leer el `$I30 de $($j.Folder)$(if ($r) { ": $($r.Error)" })"; continue }
        $slack = 0
        foreach ($e in $r.Rows) {
            $rowsI30.Add([pscustomobject]@{
                Carpeta = $j.Folder; Name = $e.Name; NameType = $e.NameType; Size = $e.Size; AllocatedSize = $e.AllocatedSize
                Mtime = $e.Mtime; Atime = $e.Atime; Ctime = $e.Ctime; Btime = $e.Btime })
            if ($e.Name -like '*(slack @ 0x*)') { $slack++ }
        }
        $how = if ($r.Fallback) { ' (carpeta pequena, leida con stat --i30)' } else { '' }
        Ok ("`$I30 {0}: {1} entradas, {2} en slack{3}" -f $j.Folder, $r.Rows.Count, $slack, $how)
    }
    $pool.Close(); $pool.Dispose()

    if ($rowsI30.Count -gt 0) {
        $i30csv = Join-Path $OutDir 'I30.csv'
        $rowsI30 | Export-Csv -Path $i30csv -NoTypeInformation -Encoding UTF8
        Ok "`$I30 -> I30.csv  ($($rowsI30.Count) entradas)"
        $results += $i30csv
    }
    else { Fail "No se saco ninguna entrada del `$I30." }
}

if ($nltProc) {
    if ($doI30) { Write-Host "" }
    Complete-LogFile
}

# ---------- Resumen de ejecutables ----------
# Todo lo que puede ejecutar codigo: binarios, librerias, Java, Python, scripts de Windows y los
# formatos tipicos de autoclickers (AutoHotkey, AutoIt).
$ExecExt = @('exe', 'dll', 'jar', 'class', 'py', 'pyw', 'pyc', 'bat', 'cmd', 'ps1', 'psm1', 'vbs', 'vbe',
             'js', 'jse', 'wsf', 'hta', 'scr', 'msi', 'sys', 'cpl', 'ocx', 'ahk', 'au3')

function Get-Ext([string]$name) {
    $n = ($name -replace ' \(slack @ 0x[0-9a-fA-F]+\)$', '').Trim()
    # Cada PowerShell que se abre crea y borra en %TEMP% estos dos archivos: ruido, no ejecutables reales.
    if ($n -like '__PSScriptPolicyTest_*') { return $null }
    $i = $n.LastIndexOf('.')
    if ($i -lt 0 -or $i -eq $n.Length - 1) { return $null }
    $e = $n.Substring($i + 1).ToLowerInvariant()
    if ($ExecExt -contains $e) { return $e } else { return $null }
}

function Write-ExecSummary {
    $found = New-Object System.Collections.Generic.List[object]

    if ($i30csv -and (Test-Path $i30csv)) {
        foreach ($r in (Import-Csv $i30csv)) {
            $e = Get-Ext $r.Name
            if (-not $e) { continue }
            # Los nombres cortos 8.3 repiten el mismo archivo: fuera, salvo en el slack (a veces es lo unico que queda).
            $slack = $r.Name -match '\(slack @ 0x[0-9a-fA-F]+\)$'
            if ($r.NameType -eq 'DOS' -and -not $slack) { continue }
            $found.Add([pscustomobject]@{
                Origen = '$I30'; Evento = $(if ($slack) { 'En slack (ya no esta en la carpeta)' } else { 'En la carpeta' })
                Ext = ".$e"; Nombre = ($r.Name -replace ' \(slack @ 0x[0-9a-fA-F]+\)$', ''); Ubicacion = $r.Carpeta
                'Hora (UTC)' = ($r.Mtime -replace ' \+0000 UTC$', '' -replace '\.\d+$', '') })
        }
    }

    if ($logCsv -and (Test-Path $logCsv)) {
        $timeCol = $null
        foreach ($r in (Import-Csv $logCsv)) {
            if (-not $timeCol) { $timeCol = ($r.PSObject.Properties.Name | Where-Object { $_ -like 'EventTime*' } | Select-Object -First 1) }
            $ev = switch -Wildcard ($r.Event) {
                'File Creation*' { 'Creado' }
                'File Deletion'  { 'Borrado' }
                'Renaming File'  { 'Renombrado' }
                'Move(After)'    { 'Movido' }
                default          { $null }
            }
            if (-not $ev) { continue }
            # En un renombrado cuenta tanto el nombre viejo como el nuevo ("viejo.exe -> nuevo.txt").
            $names = @($r.'File/Directory Name')
            if ($ev -eq 'Renombrado' -and $r.Detail -match '^(.*) -> (.*)$') { $names = @($Matches[1], $Matches[2]) }
            $e = $names | ForEach-Object { Get-Ext $_ } | Where-Object { $_ } | Select-Object -First 1
            if (-not $e) { continue }
            $found.Add([pscustomobject]@{
                Origen = '$LogFile'; Evento = $ev; Ext = ".$e"
                Nombre = $(if ($ev -eq 'Renombrado') { $r.Detail } else { $r.'File/Directory Name' })
                Ubicacion = $r.'Full Path'; 'Hora (UTC)' = $r.$timeCol })
        }
    }

    Write-Host ""
    Write-Host "  Resumen de ejecutables" -ForegroundColor White
    if ($found.Count -eq 0) { Ok "No aparece ningun ejecutable."; return }

    # Tabla: una fila por extension, una columna por lo que se ha visto.
    $cols = @('En la carpeta', 'En slack (ya no esta en la carpeta)', 'Creado', 'Borrado', 'Renombrado', 'Movido')
    $short = @{ 'En la carpeta' = 'I30 carpeta'; 'En slack (ya no esta en la carpeta)' = 'I30 slack'
                'Creado' = 'Creados'; 'Borrado' = 'Borrados'; 'Renombrado' = 'Renomb.'; 'Movido' = 'Movidos' }
    Write-Host ("  {0,-7}" -f 'Ext') -NoNewline -ForegroundColor DarkGray
    foreach ($c in $cols) { Write-Host ("{0,12}" -f $short[$c]) -NoNewline -ForegroundColor DarkGray }
    Write-Host ""
    foreach ($g in ($found | Group-Object Ext | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-7}" -f $g.Name) -NoNewline
        foreach ($c in $cols) {
            $n = @($g.Group | Where-Object Evento -eq $c).Count
            $color = if ($n -eq 0) { 'DarkGray' } elseif ($c -in 'En slack (ya no esta en la carpeta)', 'Borrado', 'Renombrado') { 'Yellow' } else { 'Gray' }
            Write-Host ("{0,12}" -f $(if ($n) { $n } else { '-' })) -NoNewline -ForegroundColor $color
        }
        Write-Host ""
    }

    # Lo que mas interesa en una SS: lo que ya no esta, lo que se borro y lo que cambio de nombre.
    $hot = @($found | Where-Object { $_.Evento -in 'En slack (ya no esta en la carpeta)', 'Borrado', 'Renombrado' })
    if ($hot.Count -gt 0) {
        Write-Host ""
        Write-Host ("  Desaparecidos, borrados o renombrados ({0}, se muestran 15):" -f $hot.Count) -ForegroundColor Yellow
        foreach ($h in ($hot | Sort-Object 'Hora (UTC)' -Descending | Select-Object -First 15)) {
            Write-Host ("   {0}  {1,-10} {2}" -f $h.'Hora (UTC)', $h.Evento.Split(' ')[0], $h.Nombre) -ForegroundColor Yellow
        }
    }

    $execCsv = Join-Path $OutDir 'Ejecutables.csv'
    $found | Export-Csv -Path $execCsv -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Ok "Ejecutables -> Ejecutables.csv  ($($found.Count) entradas)"
    $script:results += $execCsv
}

Write-ExecSummary

Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue

# ---------- Abrir ----------
Write-Host ""
if ($results.Count -eq 0) { Fail "No hay resultados."; return }
Ok "Resultados en: $OutDir"
if (-not $NoOpen) {
    if (-not (Test-DesktopRuntime)) {
        Warn "Timeline Explorer necesita el .NET 9 Desktop Runtime y no esta instalado."
        if ((Read-Host "  Instalarlo ahora? (S/N)") -match '^[sSyY]') {
            Info "Instalando .NET 9 Desktop Runtime..."
            $rt = Join-Path $env:TEMP 'windowsdesktop-runtime-9-x64.exe'
            Invoke-WebRequest -Uri 'https://aka.ms/dotnet/9.0/windowsdesktop-runtime-win-x64.exe' -OutFile $rt -UseBasicParsing
            (Start-Exe $rt @('/install', '/quiet', '/norestart')).WaitForExit()
            Remove-Item $rt -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($r in $results) {
        Info "Abriendo $(Split-Path $r -Leaf) en Timeline Explorer..."
        $null = Start-Exe $tle @($r)
    }
    $null = Start-Exe (Join-Path $env:SystemRoot 'explorer.exe') @($OutDir)
}
