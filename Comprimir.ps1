param([string]$RutaEntrada = "", [string]$RutaSalida = "", [string]$RutaInforme = "")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

"Inicio: $(Get-Date)"  | Out-File -FilePath $RutaInforme -Encoding utf8

if (-not (Test-Path -LiteralPath $RutaEntrada)) { 
    Write-Host "El directorio de entrada no existe: $RutaEntrada" -ForegroundColor Red
    break 
}

if (-not (Test-Path -LiteralPath $RutaSalida)) { 
    New-Item -ItemType Directory -Path $RutaSalida -Force | Out-Null 
}

# ==============================================================================
# ASIGNACIÓN DINÁMICA DE INSTANCIA TRABAJOX (Evita que los scripts se pisen)
# ==============================================================================
$instanciaNum = 1
do {
    $directorioVirtual = "Z:\Trabajo$instanciaNum"
    $instanciaNum++
} while (Get-ChildItem -LiteralPath $directorioVirtual -Force -ErrorAction SilentlyContinue)

# Se crea y reserva la carpeta inmediatamente para que otra instancia no la tome
New-Item -ItemType Directory -Path $directorioVirtual -Force | Out-Null


# ==============================================================================
# FASE 0: RECUPERACIÓN INICIAL DE ARCHIVOS .TMP INTERRUMPIDOS
# ==============================================================================
Remove-Item -Path "$directorioVirtual\*" -Recurse -Force -ErrorAction SilentlyContinue

foreach ($tmp in (Get-ChildItem -Path $RutaEntrada -File | Where-Object Extension -eq '.tmp')) {
    $nombreRestaurado = $tmp.Name -replace '\.tmp$', ''
    $rutaRestaurada = Join-Path $RutaEntrada $nombreRestaurado

# Si está bloqueado por el otro script en ejecución, se salta y no hace nada
    $estaBloqueado = $false
    try {
        $streamPrueba = [System.IO.File]::Open($tmp.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $streamPrueba.Close()
    } catch {
        $estaBloqueado = $true
    }
    if ($estaBloqueado) { continue }

    if (-not (Test-Path -LiteralPath $rutaRestaurada)) { 
        Rename-Item -LiteralPath $tmp.FullName -NewName $nombreRestaurado -Force -ErrorAction SilentlyContinue 
    } else {
        if ($tmp.Length -eq (Get-Item -LiteralPath $rutaRestaurada).Length) { 
            Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue 
        } else { 
            $extOriginal = [System.IO.Path]::GetExtension($nombreRestaurado)
            Rename-Item -LiteralPath $tmp.FullName -NewName "${nombreRestaurado}${extOriginal}" -Force -ErrorAction SilentlyContinue 
        }
    }
}

$rutaCarpetaShutter = "C:\Program Files\Shutter Encoder\app\Library"
$rutaFFmpegShutter = Join-Path $rutaCarpetaShutter "ffmpeg.exe"

$extensionesVideo = @('.3gp', '.asf', '.avi', '.flv', '.m2ts', '.m4v', '.mkv', '.mov', '.mp4','.mpe', '.mpeg', '.mpg', '.mts', '.ogv','.rmvb', '.ts', '.vob', '.webm', '.wmv')

$indiceActual = 0
$indiceERR = 0
$tiempoGlobalInicio = Get-Date
$pesoTotalInicialBytes = 0
$pesoTotalFinalBytes = 0
$totalArchivos =0

$mismoDisco = (Get-Item -LiteralPath $RutaEntrada).PSDrive.Name -eq (Get-Item -LiteralPath $RutaSalida).PSDrive.Name


# Se filtran los vídeos válidos y se ordenan estrictamente alfabéticamente
do {
# $colaArchivos = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
   $colaArchivos = New-Object System.Collections.Generic.List[System.IO.FileInfo]
Get-ChildItem -Path $RutaEntrada -File | Where-Object { 
    $extensionesVideo -contains $_.Extension.ToLower() -and 
    $_.Name -notmatch '_H265\.mp4$' -and
    $_.Name -notmatch '_H265\.mkv$' -and
    $_.Extension -ne '.tmp'
} | Sort-Object Name | ForEach-Object { $colaArchivos.Add($_) }

$totalArchivos += $colaArchivos.Count

if ($colaArchivos.Count -eq 0) { 
    Write-Host "No se encontraron archivos de vídeo válidos para procesar en: $RutaEntrada" -ForegroundColor Yellow
#   Remove-Item -LiteralPath $directorioVirtual -Recurse -Force -ErrorAction SilentlyContinue
   break 
} else {
    Write-Host "Se van a procesar $totalArchivos archivo(s)." -ForegroundColor Green 
}
 
Write-Host "Inicio: $(Get-Date)"
Write-Host ""

while ($colaArchivos.Count -gt 0) {
     $candidatoLista = $colaArchivos[0]
     $colaArchivos.RemoveAt(0)
    $rutaArchivoOriginal = Join-Path $RutaEntrada $candidatoLista.Name
    $original = Get-Item -LiteralPath $rutaArchivoOriginal -ErrorAction SilentlyContinue
    if ($null -eq $original -or $original.Extension -eq '.tmp') { continue }
    $nombreCompleto = $original.Name
    $rutaTemporalOrigen = "$($original.FullName).tmp"
    $pesoBytesInicial = $original.Length
    $pesoInicialMB = [Math]::Round($pesoBytesInicial / 1MB, 2)
    $pesoInicialStr = "$pesoInicialMB MB"
    $inicioArchivo = Get-Date
    try { 
        Rename-Item -LiteralPath $original.FullName -NewName "$nombreCompleto.tmp" -Force -ErrorAction Stop 
        $bloqueoExclusivo = [System.IO.File]::Open($rutaTemporalOrigen, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    } catch { 
        $copiaVirtualOriginal = $null
        $rutaSalidaTemporal = $null
        continue 
    }
    $indiceActual++
    $pesoTotalInicialBytes += $pesoBytesInicial
    $rutaDestinoFallo = Join-Path $RutaEntrada "ERROR"
    $copiaVirtualOriginal = Join-Path $directorioVirtual $nombreCompleto
    $rutaSalidaTemporal = Join-Path $directorioVirtual "FF_.mkv"

    [Console]::Write("`r$([char]27)[2K$([char]27)[36mProcesando $indiceActual de $totalArchivos   $pesoInicialStr - Inicio:$inicioArchivo$([char]27)[0m")
    [Console]::Out.Flush()

  # 2. Se copia el archivo desde Origen a Z:\Trabajo con su nombre original
  #  Copy-Item -LiteralPath $rutaTemporalOrigen -Destination $copiaVirtualOriginal -Force  
      cmd.exe /c copy /b /y "$rutaTemporalOrigen" "$copiaVirtualOriginal" > $null

    # 3. Se ejecuta FFmpeg sobre Z:\Trabajo de forma limpia (sin stats ni ruido en consola) 

    Push-Location $rutaCarpetaShutter
    $maximo = (Get-Item -LiteralPath $copiaVirtualOriginal).Length 

# Extracción automática de la tasa de fotogramas mediante ffprobe
    $ffprobePath = $rutaFFmpegShutter -replace "ffmpeg\.exe", "ffprobe.exe"
    $fpsRaw = & "$ffprobePath" -v quiet -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$copiaVirtualOriginal" 2>$null
    $framerateArgs = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($fpsRaw) -and $fpsRaw.Trim() -ne "0/0") { @("-r", $fpsRaw.Trim()) } else { @() }

& "$rutaFFmpegShutter" -strict experimental -hide_banner -threads 0 -hwaccel auto -nostdin -nostats -loglevel quiet -i "$copiaVirtualOriginal" -fs $maximo @framerateArgs -vf "scale='min(1920,iw)':-2:flags=lanczos" -c:v hevc_nvenc -b_ref_mode 0 -crf $env:QC -qp $env:QC -profile:v main -map v:0? -c:a copy -map a? -pix_fmt yuv420p -tag:v hvc1 -y "$rutaSalidaTemporal"   2>&1 | Out-Null

 # >$null 2>$null

 # write-Host "MIRA..."
 # pause

 Pop-Location

 # Comprobación unificada de errores o archivos corruptos/inválidos
 Start-Sleep -Milliseconds 100

 $pesoBytesGenerado = if (Test-Path -LiteralPath $rutaSalidaTemporal) { (Get-Item -LiteralPath $rutaSalidaTemporal).Length } else { 0 }

    if ($LASTEXITCODE -ne 0 -or $pesoBytesGenerado -le 10240 -or ([double]$pesoBytesGenerado -lt ([double]$pesoBytesInicial * 0.1))) {
        try {
            Move-Item -LiteralPath $rutaTemporalOrigen -Destination "$rutaDestinoFallo\$nombreCompleto" -Force -ErrorAction Stop
        } catch {
            Write-Host "[ADVERTENCIA] No se pudo mover el archivo corrupto en este ciclo: ($nombreCompleto)" -ForegroundColor Yellow
        }
        Remove-Item -Path "$directorioVirtual\*" -Recurse -Force -ErrorAction SilentlyContinue
        $indiceERR++
        [Console]::Write("`r$([char]27)[2K[Procesando $indiceActual de $totalArchivos]   $pesoInicialStr -> ERR`n")
        continue
    }

    if ([double]$pesoBytesGenerado -ge [double]$maximo) {
       Copy-Item -LiteralPath $copiaVirtualOriginal -Destination $rutaSalidaTemporal -Force
    }
 
# write-Host "AQUI"
# pause
    $pesoGeneradoMB = [Math]::Round($pesoBytesGenerado / 1MB, 2) 
    $pesoGeneradoStr = "$pesoGeneradoMB MB"
    

    # Determinación del peso final real

    $pesoBytesFinal = if ((Get-Item -LiteralPath $rutaSalidaTemporal).Length -lt $pesoBytesInicial) { (Get-Item -LiteralPath $rutaSalidaTemporal).Length } else { $pesoBytesInicial }
    $pesoTotalFinalBytes +=$pesoBytesFinal

    if ($null -ne $bloqueoExclusivo) { $bloqueoExclusivo.Close(); $bloqueoExclusivo = $null }
#    $bloqueoExclusivo.Close() 2>$null

    $finArchivo = Get-Date
    $duracionArchivo = $finArchivo -$inicioArchivo
    $duracionFormateada =$duracionArchivo.ToString("hh\:mm\:ss")

    $pesoFinalMB = [Math]::Round($pesoBytesFinal / 1MB, 2)
    $diferencia = $pesoFinalMB -$pesoInicialMB
    if ($pesoInicialMB -gt 0) {
        $porcentaje = [Math]::Round(($diferencia / $pesoInicialMB) * 100)     } else {$porcentaje = 0
    }
    $porcentajeStr = if ($porcentaje -ge 0) { "+$porcentaje%" } else { "$porcentaje%" }
    $velocidadStr = if ($duracionArchivo.TotalSeconds -gt 0) { $s = $pesoBytesInicial / $duracionArchivo.TotalSeconds; "$([Math]::Round($s / 1MB, 2)) MB/s" } else { "0 MB/s" }

$lineaInformeArchivo = "Procesando $indiceActual + $indiceERR  de $totalArchivos  $pesoInicialStr -> $pesoGeneradoStr    ($porcentajeStr)    Tiempo: $duracionFormateada    Vel:$velocidadStr"
Add-Content -Path $RutaInforme -Value $lineaInformeArchivo -Encoding utf8

      $origenInfo = Get-Item -LiteralPath $copiaVirtualOriginal -ErrorAction SilentlyContinue   2>$null
        $generadoInfo = Get-Item -LiteralPath $rutaSalidaTemporal

        $destinoFinal = Join-Path $RutaSalida $nombreCompleto

        # 4. Se comparan los tamaños en bytes
        if ($generadoInfo.Length -lt $origenInfo.Length) {
            # ==============================================================================
            # CASO B: EL MÁS PEQUEÑO ES EL COMPRIMIDO
            # ==============================================================================           
 
            if (Test-Path -LiteralPath $destinoFinal) {
                if ((Get-Item -LiteralPath $destinoFinal).Length -eq $generadoInfo.Length) {
                    # SI EXISTE Y TIENE LA MISMA LONGITUD: No se hace nada
                } else {
                    $nombreFinalColision = "${nombreCompleto}.mkv"
                    Copy-Item -LiteralPath $generadoInfo.FullName -Destination (Join-Path $RutaSalida $nombreFinalColision) -Force
                }
            } else {
                Copy-Item -LiteralPath $generadoInfo.FullName -Destination $destinoFinal -Force
            }
        } 
        else {
            # ==============================================================================
            # CASO A: EL MÁS PEQUEÑO ES EL ORIGINAL
            # ==============================================================================
            if (Test-Path -LiteralPath $destinoFinal) {
                $mismoTamano = (Get-Item -LiteralPath $destinoFinal).Length -eq $origenInfo.Length
                if ($mismoTamano) {
                } else {
                    $nombreFinalColision = "${nombreCompleto}.mkv"
                    $destinoFinalColision = Join-Path $RutaSalida $nombreFinalColision
                    Copy-Item -LiteralPath $origenInfo.FullName -Destination $destinoFinalColision -Force -ErrorAction SilentlyContinue 2>$null
                }
            } else {
                if ($mismoDisco) {
                    Rename-Item -LiteralPath $rutaTemporalOrigen -NewName $nombreCompleto -Force
                    $rutaRestaurada = Join-Path $RutaEntrada $nombreCompleto
		 try {
                    Move-Item -LiteralPath $rutaRestaurada -Destination $destinoFinal -Force

 	         } catch {
                # Si Windows bloquea el movimiento, lo volvemos a marcar para que nadie lo pise
                 Rename-Item -LiteralPath $rutaRestaurada -NewName "$nombreCompleto.tmp" -Force -ErrorAction SilentlyContinue
                 Write-Host "[ADVERTENCIA] Bloqueo al mover el original de: $nombreCompleto" -ForegroundColor Yellow
                }
                } else {
                    Copy-Item -LiteralPath $origenInfo.FullName -Destination $destinoFinal -Force -ErrorAction SilentlyContinue 2>$null
                }
            }
        }

[Console]::Write("`r$([char]27)[2K[Procesando $indiceActual + $indiceERR de $totalArchivos]   $pesoInicialStr -> $pesoGeneradoStr    ($porcentajeStr)    Tiempo: $duracionFormateada    Vel: $velocidadStr`n")

# ==============================================================================
    # LIMPIEZA FINAL DEL CICLO EN Z:\TRABAJO Y CARPETA ERROR SI ESTA VACIA
    # ==============================================================================
    Remove-Item -LiteralPath $rutaTemporalOrigen -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$directorioVirtual\*" -Recurse -Force -ErrorAction SilentlyContinue
  }
} while ($true)
 
Remove-Item -LiteralPath $directorioVirtual -Recurse -Force -ErrorAction SilentlyContinue

#  Remove-Item -LiteralPath "$directorioVirtual" -Recurse -Force -ErrorAction SilentlyContinue
   
# Salto de línea final para limpiar la consola tras el contador dinámico
Write-Host ""

# ==============================================================================
# BLOQUE FINAL DE TOTALES Y CIERRE
# ==============================================================================
$tiempoGlobalFin = Get-Date
$duracionGlobal = $tiempoGlobalFin - $tiempoGlobalInicio
$duracionGlobalFormateada = $duracionGlobal.ToString("hh\:mm\:ss")

# Función auxiliar para formatear gigabytes/megabytes de forma legible
function Formatear-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } else {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
}

$pesoTotalInicialStr = Formatear-Bytes $pesoTotalInicialBytes
$pesoTotalFinalStr = Formatear-Bytes $pesoTotalFinalBytes

Write-Host "Fin: $tiempoGlobalFin"
Write-Host ""
$diferenciaGlobal = $pesoTotalFinalBytes -$pesoTotalInicialBytes
if ($pesoTotalInicialBytes -gt 0) {
    $porcentajeGlobal = [Math]::Round(($diferenciaGlobal / $pesoTotalInicialBytes) * 100) } else {$porcentajeGlobal = 0
}
$porcentajeGlobalStr = if ($porcentajeGlobal -ge 0) { "+$porcentajeGlobal%" } else { "$porcentajeGlobal%" }
$velocidadGlobalStr = if ($duracionGlobal.TotalSeconds -gt 0) { $sg = $pesoTotalInicialBytes / $duracionGlobal.TotalSeconds; "$([Math]::Round($sg / 1MB, 2)) MB/s" } else { "0 MB/s" }

Add-Content -Path $RutaInforme -Value "__________" -Encoding utf8

Add-Content -Path $RutaInforme -Value "TOTALES:  $pesoTotalInicialStr -> $pesoTotalFinalStr    ($porcentajeGlobalStr)    Tiempo: $duracionGlobalFormateada    Vel:$velocidadGlobalStr" -Encoding utf8

# Write-Host ("TOTALES:`t`t{0} -> {1}    `t({2})    `tTiempo: {3}    `tVel: {4}" -f $pesoTotalInicialStr, $pesoTotalFinalStr,$porcentajeGlobalStr, 
# $duracionGlobalFormateada,$velocidadGlobalStr)

Write-Host "    TOTALES:      $pesoTotalInicialStr -> $pesoTotalFinalStr    ($porcentajeGlobalStr)    Tiempo: $duracionGlobalFormateada    Vel:$velocidadGlobalStr" 
Write-Host ""