param([string]$RutaEntrada = "", [string]$RutaSalida = "", [string]$RutaInforme = "")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

"Start: $(Get-Date)"  | Out-File -FilePath $RutaInforme -Encoding utf8

if (-not (Test-Path -LiteralPath $RutaEntrada)) { 
    Write-Host "The input directory does not exist: $RutaEntrada" -ForegroundColor Red
    break 
}

if (-not (Test-Path -LiteralPath $RutaSalida)) { 
    New-Item -ItemType Directory -Path $RutaSalida -Force | Out-Null 
}

# ==============================================================================
# DYNAMIC ALLOCATION OF WORKX INSTANCE (Prevents scripts from overlapping)
# ==============================================================================
$instanciaNum = 1
do {
    $directorioVirtual = "Z:\Trabajo$instanciaNum"
    $instanciaNum++
} while (Get-ChildItem -LiteralPath $directorioVirtual -Force -ErrorAction SilentlyContinue)

# Create and reserve the folder immediately so another instance doesn't take it
New-Item -ItemType Directory -Path $directorioVirtual -Force | Out-Null


# ==============================================================================
# PHASE 0: INITIAL RECOVERY OF INTERRUPTED .TMP FILES
# ==============================================================================
Remove-Item -Path "$directorioVirtual\*" -Recurse -Force -ErrorAction SilentlyContinue

foreach ($tmp in (Get-ChildItem -Path $RutaEntrada -File | Where-Object Extension -eq '.tmp')) {
    $nombreRestaurado = $tmp.Name -replace '\.tmp$', ''
    $rutaRestaurada = Join-Path $RutaEntrada $nombreRestaurado

# If it is locked by the other running script, it skips and does nothing
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

$RutaCarpetaOtros = Join-Path $PSScriptRoot "Others"
$RutaFfmpeg = Join-Path $RutaCarpetaOtros "ffmpeg.exe"
$RutaFfprobe = $RutaFfmpeg -replace "ffmpeg\.exe", "ffprobe.exe"

$extensionesVideo = @('.3gp', '.asf', '.avi', '.flv', '.m2ts', '.m4v', '.mkv', '.mov', '.mp4','.mpe', '.mpeg', '.mpg', '.mts', '.ogv','.rmvb', '.ts', '.vob', '.webm', '.wmv')

$indiceActual = 0
$indiceERR = 0
$tiempoGlobalInicio = Get-Date
$pesoTotalInicialBytes = 0
$pesoTotalFinalBytes = 0
$totalArchivos =0

$mismoDisco = (Get-Item -LiteralPath $RutaEntrada).PSDrive.Name -eq (Get-Item -LiteralPath $RutaSalida).PSDrive.Name


# Valid videos are filtered and strictly sorted alphabetically
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
    Write-Host "No valid video files were found to process in: $RutaEntrada" -ForegroundColor Yellow
#   Remove-Item -LiteralPath $directorioVirtual -Recurse -Force -ErrorAction SilentlyContinue
   break 
} else {
    Write-Host "Processing $totalArchivos archivo(s)." -ForegroundColor Green 
}
 
Write-Host "Start: $(Get-Date)"
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

    [Console]::Write("`r$([char]27)[2K$([char]27)[36mProcessing $indiceActual de $totalArchivos   $pesoInicialStr - Inicio:$inicioArchivo$([char]27)[0m")
    [Console]::Out.Flush()

  # 2. Copy file from Source to Z:\WorkX with its original name
  #  Copy-Item -LiteralPath $rutaTemporalOrigen -Destination $copiaVirtualOriginal -Force  
      cmd.exe /c copy /b /y "$rutaTemporalOrigen" "$copiaVirtualOriginal" > $null

    # 3. FFmpeg is executed on Z:\Trabajo cleanly (without stats or console noise)
    Push-Location $RutaCarpetaOtros
    $maximo = (Get-Item -LiteralPath $copiaVirtualOriginal).Length 

# Automatic frame rate extraction via ffprobe
   $FpsBruto = & "$RutaFfprobe" -v quiet -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$copiaVirtualOriginal" 2>$null
    $ArgTasa = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($FpsBruto) -and $FpsBruto.Trim() -ne "0/0") { @("-r", $FpsBruto.Trim()) } else { @() }

& "$RutaFfmpeg" -strict experimental -hide_banner -threads 0 -hwaccel auto -nostdin -nostats -loglevel quiet -i "$copiaVirtualOriginal" -fs $maximo @ArgTasa -vf "scale='min(1920,iw)':-2:flags=lanczos" -c:v hevc_nvenc -b_ref_mode 0 -crf $env:QC -qp $env:QC -profile:v main -map v:0? -c:a copy -map a? -pix_fmt yuv420p -tag:v hvc1 -y "$rutaSalidaTemporal"   2>&1 | Out-Null

 Pop-Location

 # Error or corrupt/invalid files unified check
 Start-Sleep -Milliseconds 100

 $pesoBytesGenerado = if (Test-Path -LiteralPath $rutaSalidaTemporal) { (Get-Item -LiteralPath $rutaSalidaTemporal).Length } else { 0 }

    if ($LASTEXITCODE -ne 0 -or $pesoBytesGenerado -le 10240 -or ([double]$pesoBytesGenerado -lt ([double]$pesoBytesInicial * 0.1))) {
        try {
            Move-Item -LiteralPath $rutaTemporalOrigen -Destination "$rutaDestinoFallo\$nombreCompleto" -Force -ErrorAction Stop
        } catch {
            Write-Host "[WARNING] Could not move corrupt file in this cycle: ($nombreCompleto)" -ForegroundColor Yellow
        }
        Remove-Item -Path "$directorioVirtual\*" -Recurse -Force -ErrorAction SilentlyContinue
        $indiceERR++
        [Console]::Write("`r$([char]27)[2K[Processing $indiceActual of $totalArchivos]   $pesoInicialStr -> ERR`n")
        continue
    }

    if ([double]$pesoBytesGenerado -ge [double]$maximo) {
       Copy-Item -LiteralPath $copiaVirtualOriginal -Destination $rutaSalidaTemporal -Force
    }
 
    $pesoGeneradoMB = [Math]::Round($pesoBytesGenerado / 1MB, 2) 
    $pesoGeneradoStr = "$pesoGeneradoMB MB"
    
    # Real final size determination
    $pesoBytesFinal = if ((Get-Item -LiteralPath $rutaSalidaTemporal).Length -lt $pesoBytesInicial) { (Get-Item -LiteralPath $rutaSalidaTemporal).Length } else { $pesoBytesInicial }
    $pesoTotalFinalBytes +=$pesoBytesFinal

    if ($null -ne $bloqueoExclusivo) { $bloqueoExclusivo.Close(); $bloqueoExclusivo = $null }

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

$lineaInformeArchivo = "Processing $indiceActual + $indiceERR  de $totalArchivos  $pesoInicialStr -> $pesoGeneradoStr    ($porcentajeStr)    Time: $duracionFormateada    Speed:$velocidadStr"
Add-Content -Path $RutaInforme -Value $lineaInformeArchivo -Encoding utf8

      $origenInfo = Get-Item -LiteralPath $copiaVirtualOriginal -ErrorAction SilentlyContinue   2>$null
        $generadoInfo = Get-Item -LiteralPath $rutaSalidaTemporal

        $destinoFinal = Join-Path $RutaSalida $nombreCompleto

        # 4. Byte sizes comparison
        if ($generadoInfo.Length -lt $origenInfo.Length) {
            # ==============================================================================
            # CASE B: THE COMPRESSED ONE IS SMALLER
            # ==============================================================================           
 
            if (Test-Path -LiteralPath $destinoFinal) {
                if ((Get-Item -LiteralPath $destinoFinal).Length -eq $generadoInfo.Length) {
                    # Do nothing
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
            # CASE A: THE ORIGINAL ONE IS SMALLER
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
                # If Windows locks the move operation, mark it as .tmp again
                 Rename-Item -LiteralPath $rutaRestaurada -NewName "$nombreCompleto.tmp" -Force -ErrorAction SilentlyContinue
                 Write-Host "[WARNING] File lock while moving the original file from: $nombreCompleto" -ForegroundColor Yellow
                }
                } else {
                    Copy-Item -LiteralPath $origenInfo.FullName -Destination $destinoFinal -Force -ErrorAction SilentlyContinue 2>$null
                }
            }
        }

[Console]::Write("`r$([char]27)[2K[Processing $indiceActual + $indiceERR of $totalArchivos]   $pesoInicialStr -> $pesoGeneradoStr    ($porcentajeStr)    Time: $duracionFormateada    Speed: $velocidadStr`n")

# ==============================================================================
    # CYCLE END CLEANUP IN Z:\WORK AND FAILURES FOLDER IF EMPTY
    # ==============================================================================
    Remove-Item -LiteralPath $rutaTemporalOrigen -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$directorioVirtual\*" -Recurse -Force -ErrorAction SilentlyContinue
  }
} while ($true)
 
Remove-Item -LiteralPath $directorioVirtual -Recurse -Force -ErrorAction SilentlyContinue

#  Remove-Item -LiteralPath "$directorioVirtual" -Recurse -Force -ErrorAction SilentlyContinue
   
# Final line break to clear the console after the dynamic counter
Write-Host ""

# ==============================================================================
# TOTALS AND END BLOCK
# ==============================================================================
$tiempoGlobalFin = Get-Date
$duracionGlobal = $tiempoGlobalFin - $tiempoGlobalInicio
$duracionGlobalFormateada = $duracionGlobal.ToString("hh\:mm\:ss")

# Helper function to format gigabytes/megabytes in a human-readable format
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

Write-Host "End: $tiempoGlobalFin"
Write-Host ""
$diferenciaGlobal = $pesoTotalFinalBytes -$pesoTotalInicialBytes
if ($pesoTotalInicialBytes -gt 0) {
    $porcentajeGlobal = [Math]::Round(($diferenciaGlobal / $pesoTotalInicialBytes) * 100) } else {$porcentajeGlobal = 0
}
$porcentajeGlobalStr = if ($porcentajeGlobal -ge 0) { "+$porcentajeGlobal%" } else { "$porcentajeGlobal%" }
$velocidadGlobalStr = if ($duracionGlobal.TotalSeconds -gt 0) { $sg = $pesoTotalInicialBytes / $duracionGlobal.TotalSeconds; "$([Math]::Round($sg / 1MB, 2)) MB/s" } else { "0 MB/s" }

Add-Content -Path $RutaInforme -Value "__________" -Encoding utf8

Add-Content -Path $RutaInforme -Value "TOTALS:  $pesoTotalInicialStr -> $pesoTotalFinalStr    ($porcentajeGlobalStr)    Time: $duracionGlobalFormateada    Speed:$velocidadGlobalStr" -Encoding utf8

Write-Host "    TOTALS:      $pesoTotalInicialStr -> $pesoTotalFinalStr    ($porcentajeGlobalStr)    Time: $duracionGlobalFormateada    Speed:$velocidadGlobalStr" 
Write-Host ""