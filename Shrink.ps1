param([string]$InputPath = "", [string]$CustomOutputPath = "", [string]$ReportPath = "")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

"Start: $(Get-Date)"  | Out-File -FilePath $ReportPath -Encoding utf8

$workingDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$inputDirectory = if ($InputPath -ne "") { $InputPath } else { Join-Path $workingDirectory "Failures" }

if (-not (Test-Path -LiteralPath $inputDirectory)) { 
    Write-Host "The input directory does not exist: $inputDirectory" -ForegroundColor Red
    Remove-Item -LiteralPath $virtualDirectory -Recurse -Force -ErrorAction SilentlyContinue
    break 
}

$outputDirectory = if ($CustomOutputPath -ne "") { $CustomOutputPath } else { Join-Path $workingDirectory "Salida" }

if (-not (Test-Path -LiteralPath $outputDirectory)) { 
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null 
}

# ==============================================================================
# DYNAMIC ALLOCATION OF WORKX INSTANCE (Prevents scripts from overlapping)
# ==============================================================================
$instanceNum = 1
do {
    $virtualDirectory = "Z:\Work$instanceNum"
    $instanceNum++
} while (Get-ChildItem -LiteralPath $virtualDirectory -Force -ErrorAction SilentlyContinue)

# Create and reserve the folder immediately so another instance doesn't take it
New-Item -ItemType Directory -Path $virtualDirectory -Force | Out-Null

# ==============================================================================
# PHASE 0: INITIAL RECOVERY OF INTERRUPTED .TMP FILES
# ==============================================================================
Remove-Item -Path "$virtualDirectory\*" -Recurse -Force -ErrorAction SilentlyContinue

foreach ($tmp in (Get-ChildItem -Path $inputDirectory -File | Where-Object Extension -eq '.tmp')) {
    $restoredName = $tmp.Name -replace '\.tmp$', ''
    $restoredPath = Join-Path $inputDirectory $restoredName

    # If it is locked by another running script, skip it and do nothing
    $isLocked = $false
    try {
        $testStream = [System.IO.File]::Open($tmp.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $testStream.Close()
    } catch {
        $isLocked = $true
    }
    if ($isLocked) { continue }

    if (-not (Test-Path -LiteralPath $restoredPath)) { 
        Rename-Item -LiteralPath $tmp.FullName -NewName $restoredName -Force -ErrorAction SilentlyContinue 
    } else {
        if ($tmp.Length -eq (Get-Item -LiteralPath $restoredPath).Length) { 
            Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue 
        } else { 
            $originalExt = [System.IO.Path]::GetExtension($restoredName)
            Rename-Item -LiteralPath $tmp.FullName -NewName "${restoredName}${originalExt}" -Force -ErrorAction SilentlyContinue 
        }
    }
}

$shutterFolderPath = Join-Path  $PSScriptRoot "Others"
$shutterFFmpegPath = Join-Path  $shutterFolderPath "ffmpeg.exe"

$videoExtensions = @('.3gp', '.asf', '.avi', '.flv', '.m2ts', '.m4v', '.mkv', '.mov', '.mp4','.mpe', '.mpeg', '.mpg', '.mts', '.ogv','.rmvb', '.ts', '.vob', '.webm', '.wmv')

$currentIndex = 0
$errorIndex = 0
$globalStartTime = Get-Date
$totalInitialBytes = 0
$totalFinalBytes = 0
$totalFiles = 0

$sameDrive = (Get-Item -LiteralPath $inputDirectory).PSDrive.Name -eq (Get-Item -LiteralPath $outputDirectory).PSDrive.Name

# Valid videos are filtered and strictly sorted alphabetically
do {
    $fileQueue = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    Get-ChildItem -Path $inputDirectory -File | Where-Object { 
        $videoExtensions -contains $_.Extension.ToLower() -and 
        $_.Name -notmatch '_H265\.mp4$' -and
        $_.Name -notmatch '_H265\.mkv$' -and
        $_.Extension -ne '.tmp'
    } | Sort-Object Name | ForEach-Object { $fileQueue.Add($_) }

    $totalFiles += $fileQueue.Count

    if ($fileQueue.Count -eq 0) { 
        Write-Host "No valid video files were found to process in: $inputDirectory" -ForegroundColor Yellow
        Remove-Item -LiteralPath $virtualDirectory -Recurse -Force -ErrorAction SilentlyContinue
        break 
    } else {
        Write-Host "Processing $totalFiles file(s)." -ForegroundColor Green 
    }
     
    # Ensure that the internal FAILURES folder exists to isolate corrupt videos
    $internalFailuresFolder = Join-Path $inputDirectory "Failures"
    if (-not (Test-Path -LiteralPath $internalFailuresFolder)) {
        New-Item -ItemType Directory -Path $internalFailuresFolder -Force | Out-Null
    }

    Write-Host "Start: $(Get-Date)"
    Write-Host ""

    while ($fileQueue.Count -gt 0) {
        $listCandidate = $fileQueue[0]
        $fileQueue.RemoveAt(0)
        $originalFilePath = Join-Path $inputDirectory $listCandidate.Name
        $original = Get-Item -LiteralPath $originalFilePath -ErrorAction SilentlyContinue
        if ($null -eq $original -or $original.Extension -eq '.tmp') { continue }
        $fullName = $original.Name
        $sourceTemporaryPath = "$($original.FullName).tmp"
        $initialBytesWeight = $original.Length
        $initialWeightMB = [Math]::Round($initialBytesWeight / 1MB, 2)
        $initialWeightStr = "$initialWeightMB MB"
        $fileStartTime = Get-Date
        try { 
            Rename-Item -LiteralPath $original.FullName -NewName "$fullName.tmp" -Force -ErrorAction Stop 
            $exclusiveLock = [System.IO.File]::Open($sourceTemporaryPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        } catch { 
            $originalVirtualCopy = $null
            $temporaryOutputPath = $null
            continue 
        }
        $currentIndex++
        $totalInitialBytes += $initialBytesWeight
        $failureDestinationPath = Join-Path $internalFailuresFolder $fullName
        $originalVirtualCopy = Join-Path $virtualDirectory $fullName
        $temporaryOutputPath = Join-Path $virtualDirectory "FF_.mkv"

        [Console]::Write("`r$([char]27)[2K$([char]27)[36mProcessing $currentIndex of $totalFiles   $initialWeightStr - Start:$fileStartTime$([char]27)[0m")
        [Console]::Out.Flush()

        # 2. Copy file from Source to Z:\Work with its original name
        cmd.exe /c copy /b /y "$sourceTemporaryPath" "$originalVirtualCopy" > $null

        # 3. Run FFmpeg over Z:\Work cleanly
        Push-Location $shutterFolderPath
        $maxSize = (Get-Item -LiteralPath $originalVirtualCopy).Length 

        # Automatic frame rate extraction via ffprobe
        $ffprobePath = $shutterFFmpegPath -replace "ffmpeg\.exe", "ffprobe.exe"
        $fpsRaw = & "$ffprobePath" -v quiet -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$originalVirtualCopy" 2>$null
        $framerateArgs = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($fpsRaw) -and $fpsRaw.Trim() -ne "0/0") { @("-r", $fpsRaw.Trim()) } else { @() }

        & "$shutterFFmpegPath" -strict experimental -hide_banner -threads 0 -hwaccel auto -nostdin -nostats -loglevel quiet -i "$originalVirtualCopy" -fs $maxSize @framerateArgs -vf "scale='min(1920,iw)':-2:flags=lanczos" -c:v hevc_nvenc -b_ref_mode 0 -crf $env:QC -qp $env:QC -profile:v main -map v:0? -c:a copy -map a? -pix_fmt yuv420p -tag:v hvc1 -y "$temporaryOutputPath" 2>&1 | Out-Null

        Pop-Location

        # Error or corrupt/invalid files unified check
        Start-Sleep -Milliseconds 100

        $generatedBytesWeight = if (Test-Path -LiteralPath $temporaryOutputPath) { (Get-Item -LiteralPath $temporaryOutputPath).Length } else { 0 }

        if ($LASTEXITCODE -ne 0 -or $generatedBytesWeight -le 10240 -or ([double]$generatedBytesWeight -lt ([double]$initialBytesWeight * 0.1))) {
            try {
                Move-Item -LiteralPath $sourceTemporaryPath -Destination $failureDestinationPath -Force -ErrorAction Stop
            } catch {
                Write-Host "[WARNING] Could not move corrupt file in this cycle: ($fullName)" -ForegroundColor Yellow
            }
            Remove-Item -Path "$virtualDirectory\*" -Recurse -Force -ErrorAction SilentlyContinue
            $errorIndex++
            [Console]::Write("`r$([char]27)[2K[Processing $currentIndex of $totalFiles]   $initialWeightStr -> ERR`n")
            continue
        }

        if ([double]$generatedBytesWeight -ge [double]$maxSize) {
           Copy-Item -LiteralPath $originalVirtualCopy -Destination $temporaryOutputPath -Force
        }
     
        $sourceInfo = Get-Item -LiteralPath $originalVirtualCopy -ErrorAction SilentlyContinue 2>$null

        $generatedWeightMB = [Math]::Round($generatedBytesWeight / 1MB, 2) 
        $generatedWeightStr = "$generatedWeightMB MB"
        
        # Real final size determination
        $finalBytesWeight = if ((Get-Item -LiteralPath $temporaryOutputPath).Length -lt $initialBytesWeight) { (Get-Item -LiteralPath $temporaryOutputPath).Length } else { $initialBytesWeight }
        $totalFinalBytes += $finalBytesWeight

        if ($null -ne $exclusiveLock) { $exclusiveLock.Close(); $exclusiveLock = $null }

        $fileEndTime = Get-Date
        $fileDuration = $fileEndTime - $fileStartTime
        $formattedDuration = $fileDuration.ToString("hh\:mm\:ss")

        $finalWeightMB = [Math]::Round($finalBytesWeight / 1MB, 2)
        $difference = $finalWeightMB - $initialWeightMB
        if ($initialWeightMB -gt 0) {
            $percentage = [Math]::Round(($difference / $initialWeightMB) * 100)
        } else {
            $percentage = 0
        }
        $percentageStr = if ($percentage -ge 0) { "+$percentage%" } else { "$percentage%" }
        $speedStr = if ($fileDuration.TotalSeconds -gt 0) { $s = $initialBytesWeight / $fileDuration.TotalSeconds; "$([Math]::Round($s / 1MB, 2)) MB/s" } else { "0 MB/s" }

        $reportLineFile = "Processing $currentIndex + $errorIndex of $totalFiles  $initialWeightStr -> $generatedWeightStr    ($percentageStr)    Time: $formattedDuration    Speed:$speedStr"
        Add-Content -Path $ReportPath -Value $reportLineFile -Encoding utf8

        $sourceInfo = Get-Item -LiteralPath $originalVirtualCopy -ErrorAction SilentlyContinue 2>$null
        $generatedInfo = Get-Item -LiteralPath $temporaryOutputPath

        $finalDestination = Join-Path $outputDirectory $fullName

        # 4. Byte sizes comparison
        if ($generatedInfo.Length -lt $sourceInfo.Length) {
            # ==============================================================================
            # CASE B: THE COMPRESSED ONE IS SMALLER
            # ==============================================================================           
            if (Test-Path -LiteralPath $finalDestination) {
                if ((Get-Item -LiteralPath $finalDestination).Length -eq $generatedInfo.Length) {
                    # IF IT EXISTS AND HAS THE SAME LENGTH: Do nothing
                } else {
                    $collisionFinalName = "${fullName}.mkv"
                    Copy-Item -LiteralPath $generatedInfo.FullName -Destination (Join-Path $outputDirectory $collisionFinalName) -Force
                }
            } else {
                Copy-Item -LiteralPath $generatedInfo.FullName -Destination $finalDestination -Force
            }
        } 
        else {
            # ==============================================================================
            # CASE A: THE ORIGINAL ONE IS SMALLER
            # ==============================================================================
            if (Test-Path -LiteralPath $finalDestination) {
                $sameSize = (Get-Item -LiteralPath $finalDestination).Length -eq $sourceInfo.Length
                if ($sameSize) {
                    # Do nothing
                } else {
                    $collisionFinalName = "${fullName}.mkv"
                    $collisionFinalDestination = Join-Path $outputDirectory $collisionFinalName
                    Copy-Item -LiteralPath $sourceInfo.FullName -Destination $collisionFinalDestination -Force -ErrorAction SilentlyContinue 2>$null
                }
            } else {
                if ($sameDrive) {
                    Rename-Item -LiteralPath $sourceTemporaryPath -NewName $fullName -Force
                    $restoredPath = Join-Path $inputDirectory $fullName
                    try {
                        Move-Item -LiteralPath $restoredPath -Destination $finalDestination -Force
                    } catch {
                        # If Windows locks the move operation, mark it as .tmp again
                        Rename-Item -LiteralPath $restoredPath -NewName "$fullName.tmp" -Force -ErrorAction SilentlyContinue
                        Write-Host "[WARNING] File lock while moving the original file from: $fullName" -ForegroundColor Yellow
                    }
                } else {
                    Copy-Item -LiteralPath $sourceInfo.FullName -Destination $finalDestination -Force -ErrorAction SilentlyContinue 2>$null
                }
            }
        }

        [Console]::Write("`r$([char]27)[2K[Processing $currentIndex + $errorIndex of $totalFiles]   $initialWeightStr -> $generatedWeightStr    ($percentageStr)    Time: $formattedDuration    Speed: $speedStr`n")

        # ==============================================================================
        # CYCLE END CLEANUP IN Z:\WORK AND FAILURES FOLDER IF EMPTY
        # ==============================================================================
        Remove-Item -LiteralPath $sourceTemporaryPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$virtualDirectory\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
} while ($true)

    if (Test-Path -LiteralPath $internalFailuresFolder) {
        if ((Get-ChildItem -Path $internalFailuresFolder -Force).Count -eq 0) {
            Remove-Item -LiteralPath $internalFailuresFolder -Force -ErrorAction SilentlyContinue
        }
    }

    Remove-Item -LiteralPath "$virtualDirectory" -Recurse -Force -ErrorAction SilentlyContinue

    # Final line break to clear the console after the dynamic counter
    Write-Host ""

    # ==============================================================================
    # TOTALS AND END BLOCK
    # ==============================================================================
    $globalEndTime = Get-Date
    $globalDuration = $globalEndTime - $globalStartTime
    $globalDurationFormatted = $globalDuration.ToString("hh\:mm\:ss")

    function Format-Bytes {
        param([long]$Bytes)
        if ($Bytes -ge 1GB) {
            return "{0:N2} GB" -f ($Bytes / 1GB)
        } else {
            return "{0:N2} MB" -f ($Bytes / 1MB)
        }
    }

    $totalInitialWeightStr = Format-Bytes $totalInitialBytes
    $totalFinalWeightStr = Format-Bytes $totalFinalBytes

    Write-Host "End: $globalEndTime"
    Write-Host ""
    $globalDifference = $totalFinalBytes - $totalInitialBytes
    if ($totalInitialBytes -gt 0) {
        $globalPercentage = [Math]::Round(($globalDifference / $totalInitialBytes) * 100) 
    } else {
        $globalPercentage = 0
    }
    $globalPercentageStr = if ($globalPercentage -ge 0) { "+$globalPercentage%" } else { "$globalPercentage%" }
    $globalSpeedStr = if ($globalDuration.TotalSeconds -gt 0) { $sg = $totalInitialBytes / $globalDuration.TotalSeconds; "$([Math]::Round($sg / 1MB, 2)) MB/s" } else { "0 MB/s" }

    Add-Content -Path $ReportPath -Value "__________" -Encoding utf8
    Add-Content -Path $ReportPath -Value "TOTALS:  $totalInitialWeightStr -> $totalFinalWeightStr    ($globalPercentageStr)    Time: $globalDurationFormatted    Speed:$globalSpeedStr" -Encoding utf8

    Write-Host "    TOTALS:      $totalInitialWeightStr -> $totalFinalWeightStr    ($globalPercentageStr)    Time: $globalDurationFormatted    Speed:$globalSpeedStr" 
    Write-Host ""