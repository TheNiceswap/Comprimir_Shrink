param([string]$InputPath = "", [string]$OutputPath = "", [string]$ReportPath = "", [string]$BaseWorkPath = "")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

"Start: $(Get-Date)"  | Out-File -FilePath $ReportPath -Encoding utf8

if (-not (Test-Path -LiteralPath $InputPath)) { 
    Write-Host "The input directory does not exist: $InputPath" -ForegroundColor Red
    break 
}

if (-not (Test-Path -LiteralPath $OutputPath)) { 
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null 
}

# ==============================================================================
# DYNAMIC ALLOCATION OF WORKX INSTANCE (Prevents scripts from overlapping)
# ==============================================================================
$InstanceNumIndex = 1
do {
    $VirtualWorkDir = "$BaseWorkPath\Work$InstanceNumIndex"
    $InstanceNumIndex++
} while (Get-ChildItem -LiteralPath $VirtualWorkDir -Force -ErrorAction SilentlyContinue)

# Create and reserve the folder immediately so another instance doesn't take it
New-Item -ItemType Directory -Path $VirtualWorkDir -Force | Out-Null


# ==============================================================================
# PHASE 0: INITIAL RECOVERY OF INTERRUPTED .TMP FILES
# ==============================================================================
Remove-Item -Path "$VirtualWorkDir\*" -Recurse -Force -ErrorAction SilentlyContinue

foreach ($tmp in (Get-ChildItem -Path $InputPath -File | Where-Object Extension -eq '.tmp')) {
    $RestoredName = $tmp.Name -replace '\.tmp$', ''
    $RestoredPath = Join-Path $InputPath $RestoredName

# If it is locked by the other running script, it skips and does nothing
    $Locked = $false
    try {
        $StreamProbe = [System.IO.File]::Open($tmp.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $StreamProbe.Close()
    } catch {
        $Locked = $true
    }
    if ($Locked) { continue }

    if (-not (Test-Path -LiteralPath $RestoredPath)) { 
        Rename-Item -LiteralPath $tmp.FullName -NewName $RestoredName -Force -ErrorAction SilentlyContinue 
    } else {
        if ($tmp.Length -eq (Get-Item -LiteralPath $RestoredPath).Length) { 
            Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue 
        } else { 
            $OriginalExt = [System.IO.Path]::GetExtension($RestoredName)
            Rename-Item -LiteralPath $tmp.FullName -NewName "${RestoredName}${OriginalExt}" -Force -ErrorAction SilentlyContinue 
        }
    }
}

$BinariesDir = Join-Path $PSScriptRoot "Others"
$FfmpegPath = Join-Path $BinariesDir "ffmpeg.exe"
$FfprobePath = $FfmpegPath -replace "ffmpeg\.exe", "ffprobe.exe"

$AllowedExtensions = @('.3gp', '.asf', '.avi', '.flv', '.m2ts', '.m4v', '.mkv', '.mov', '.mp4','.mpe', '.mpeg', '.mpg', '.mts', '.ogv','.rmvb', '.ts', '.vob', '.webm', '.wmv')

$ProcessedFilesCount = 0
$FailedFilesCount = 0
$GlobalStartTime = Get-Date
$TotalInitialBytes = 0
$TotalFinalBytes = 0
$TotalQueuedFiles =0

$SameDrive = (Get-Item -LiteralPath $InputPath).PSDrive.Name -eq (Get-Item -LiteralPath $OutputPath).PSDrive.Name


# Valid videos are filtered and strictly sorted alphabetically
do {
# $FileQueue = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
   $FileQueue = New-Object System.Collections.Generic.List[System.IO.FileInfo]
Get-ChildItem -Path $InputPath -File | Where-Object { 
    $AllowedExtensions -contains $_.Extension.ToLower() -and 
    $_.Name -notmatch '_H265\.mp4$' -and
    $_.Name -notmatch '_H265\.mkv$' -and
    $_.Extension -ne '.tmp'
} | Sort-Object Name | ForEach-Object { $FileQueue.Add($_) }

$TotalQueuedFiles += $FileQueue.Count

if ($FileQueue.Count -eq 0) { 
    Write-Host "No video files were found to process: $InputPath" -ForegroundColor Yellow
#   Remove-Item -LiteralPath $VirtualWorkDir -Recurse -Force -ErrorAction SilentlyContinue
   break 
} else {
    Write-Host "Processing $TotalQueuedFiles Files." -ForegroundColor Green 
}
 
Write-Host "Start: $(Get-Date)"
Write-Host ""

while ($FileQueue.Count -gt 0) {
     $CurrentFileCandidate = $FileQueue[0]
     $FileQueue.RemoveAt(0)
    $OriginalFilePath = Join-Path $InputPath $CurrentFileCandidate.Name
    $CurrentFileInfo = Get-Item -LiteralPath $OriginalFilePath -ErrorAction SilentlyContinue
    if ($null -eq $CurrentFileInfo -or $CurrentFileInfo.Extension -eq '.tmp') { continue }
    $OriginalFileName = $CurrentFileInfo.Name
    $TempSourcePath = "$($CurrentFileInfo.FullName).tmp"
    $SourceFileSizeBytes = $CurrentFileInfo.Length
    $SourceFileSizeMB = [Math]::Round($SourceFileSizeBytes / 1MB, 2)
    $SourceFileSizeStr = "$SourceFileSizeMB MB"
    $FileStartTime = Get-Date
    try { 
        Rename-Item -LiteralPath $CurrentFileInfo.FullName -NewName "$OriginalFileName.tmp" -Force -ErrorAction Stop 
        $ExclusiveFileLock = [System.IO.File]::Open($TempSourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    } catch { 
        $VirtualSourceCopy = $null
        $VirtualTempOutputPath = $null
        continue 
    }
    $ProcessedFilesCount++
    $TotalInitialBytes += $SourceFileSizeBytes
    $ErrorDestPath = Join-Path $InputPath "ERROR"
    $VirtualSourceCopy = Join-Path $VirtualWorkDir $OriginalFileName
    $VirtualTempOutputPath = Join-Path $VirtualWorkDir "FF_.mkv"

    [Console]::Write("`r$([char]27)[2K$([char]27)[36mProcessing $ProcessedFilesCount of $TotalQueuedFiles   $SourceFileSizeStr - Start:$FileStartTime$([char]27)[0m")
    [Console]::Out.Flush()

  # 2. Copy file from Source to Z:\WorkX with its original name
  #  Copy-Item -LiteralPath $TempSourcePath -Destination $VirtualSourceCopy -Force  
      cmd.exe /c copy /b /y "$TempSourcePath" "$VirtualSourceCopy" > $null

    # 3. FFmpeg is executed on Z:\Trabajo cleanly (without stats or console noise)
    Push-Location $BinariesDir
    $Maximum = (Get-Item -LiteralPath $VirtualSourceCopy).Length 

# Automatic frame rate extraction via ffprobee
   $RawFrameRate = & "$FfprobePath" -v quiet -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$VirtualSourceCopy" 2>$null
    $FfmpegFpsArg = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($RawFrameRate) -and $RawFrameRate.Trim() -ne "0/0") { @("-r", $RawFrameRate.Trim()) } else { @() }

& "$FfmpegPath" -strict experimental -hide_banner -threads 0 -hwaccel auto -nostdin -nostats -loglevel quiet -i "$VirtualSourceCopy" -fs $Maximum @FfmpegFpsArg -vf "scale='min(1920,iw)':-2:flags=lanczos" -c:v hevc_nvenc -b_ref_mode 0 -crf $env:QC -qp $env:QC -profile:v main -map v:0? -c:a copy -map a? -pix_fmt yuv420p -tag:v hvc1 -y "$VirtualTempOutputPath"   2>&1 | Out-Null

 Pop-Location

 # Error or corrupt/invalid files unified check
 Start-Sleep -Milliseconds 100

 $OutputBytesGenerated = if (Test-Path -LiteralPath $VirtualTempOutputPath) { (Get-Item -LiteralPath $VirtualTempOutputPath).Length } else { 0 }

    if ($LASTEXITCODE -ne 0 -or $OutputBytesGenerated -le 10240 -or ([double]$OutputBytesGenerated -lt ([double]$SourceFileSizeBytes * 0.1))) {
        try {
            Move-Item -LiteralPath $TempSourcePath -Destination "$ErrorDestPath\$OriginalFileName" -Force -ErrorAction Stop
        } catch {
            Write-Host "[WARNING] Could not move corrupt file in this cycle: ($OriginalFileName)" -ForegroundColor Yellow
        }
        Remove-Item -Path "$VirtualWorkDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        $FailedFilesCount++
        [Console]::Write("`r$([char]27)[2K[Processing $ProcessedFilesCount of $TotalQueuedFiles]   $SourceFileSizeStr -> ERR`n")
        continue
    }

    if ([double]$OutputBytesGenerated -ge [double]$Maximum) {
       Copy-Item -LiteralPath $VirtualSourceCopy -Destination $VirtualTempOutputPath -Force
    }
 
    $OutputSizeMB = [Math]::Round($OutputBytesGenerated / 1MB, 2) 
    $OutputSizeStr = "$OutputSizeMB MB"
    

    # Real final size determination
    $FinalFileSizeBytes = if ((Get-Item -LiteralPath $VirtualTempOutputPath).Length -lt $SourceFileSizeBytes) { (Get-Item -LiteralPath $VirtualTempOutputPath).Length } else { $SourceFileSizeBytes }
    $TotalFinalBytes +=$FinalFileSizeBytes

    if ($null -ne $ExclusiveFileLock) { $ExclusiveFileLock.Close(); $ExclusiveFileLock = $null }

    $FileEndTime = Get-Date
    $FileDuration = $FileEndTime -$FileStartTime
    $FileDurationStr =$FileDuration.ToString("hh\:mm\:ss")

    $FinalFileSizeMB = [Math]::Round($FinalFileSizeBytes / 1MB, 2)
    $SizeDifferenceMB = $FinalFileSizeMB -$SourceFileSizeMB
    if ($SourceFileSizeMB -gt 0) {
        $CompressionRatio = [Math]::Round(($SizeDifferenceMB / $SourceFileSizeMB) * 100)     } else {$CompressionRatio = 0
    }
    $CompressionRatioStr = if ($CompressionRatio -ge 0) { "+$CompressionRatio%" } else { "$CompressionRatio%" }
    $ProcessingSpeedStr = if ($FileDuration.TotalSeconds -gt 0) { $s = $SourceFileSizeBytes / $FileDuration.TotalSeconds; "$([Math]::Round($s / 1MB, 2)) MB/s" } else { "0 MB/s" }

$ReportLineStr = "Processing $ProcessedFilesCount + $FailedFilesCount of  $TotalQueuedFiles  $SourceFileSizeStr -> $OutputSizeStr    ($CompressionRatioStr)    Time: $FileDurationStr    Speed:$ProcessingSpeedStr"
Add-Content -Path $ReportPath -Value $ReportLineStr -Encoding utf8

      $VirtualSourceInfo = Get-Item -LiteralPath $VirtualSourceCopy -ErrorAction SilentlyContinue   2>$null
        $VirtualOutputInfo = Get-Item -LiteralPath $VirtualTempOutputPath

        $FinalDestinationPath = Join-Path $OutputPath $OriginalFileName

        # 4. Byte sizes comparison
        if ($VirtualOutputInfo.Length -lt $VirtualSourceInfo.Length) {
            # ==============================================================================
            # CASE B: THE COMPRESSED ONE IS SMALLER
            # ==============================================================================           
 
            if (Test-Path -LiteralPath $FinalDestinationPath) {
                if ((Get-Item -LiteralPath $FinalDestinationPath).Length -eq $VirtualOutputInfo.Length) {
                    # Do nothing
                } else {
                    $CollisionFileName = "${OriginalFileName}.mkv"
                    Copy-Item -LiteralPath $VirtualOutputInfo.FullName -Destination (Join-Path $OutputPath $CollisionFileName) -Force
                }
            } else {
                Copy-Item -LiteralPath $VirtualOutputInfo.FullName -Destination $FinalDestinationPath -Force
            }
        } 
        else {
            # ==============================================================================
            # CASE A: THE ORIGINAL ONE IS SMALLER
            # ==============================================================================
            if (Test-Path -LiteralPath $FinalDestinationPath) {
                $SameSize = (Get-Item -LiteralPath $FinalDestinationPath).Length -eq $VirtualSourceInfo.Length
                if ($SameSize) {
                } else {
                    $CollisionFileName = "${OriginalFileName}.mkv"
                    $CollisionDestPath = Join-Path $OutputPath $CollisionFileName
                    Copy-Item -LiteralPath $VirtualSourceInfo.FullName -Destination $CollisionDestPath -Force -ErrorAction SilentlyContinue 2>$null
                }
            } else {
                if ($SameDrive) {
                    Rename-Item -LiteralPath $TempSourcePath -NewName $OriginalFileName -Force
                    $RestoredPath = Join-Path $InputPath $OriginalFileName
		 try {
                    Move-Item -LiteralPath $RestoredPath -Destination $FinalDestinationPath -Force

 	         } catch {
                # If Windows locks the move operation, mark it as .tmp again
                 Rename-Item -LiteralPath $RestoredPath -NewName "$OriginalFileName.tmp" -Force -ErrorAction SilentlyContinue
                 Write-Host "[WARNING] File lock while moving the original file from: $OriginalFileName" -ForegroundColor Yellow
                }
                } else {
                    Copy-Item -LiteralPath $VirtualSourceInfo.FullName -Destination $FinalDestinationPath -Force -ErrorAction SilentlyContinue 2>$null
                }
            }
        }

[Console]::Write("`r$([char]27)[2K[Processing $ProcessedFilesCount + $FailedFilesCount of $TotalQueuedFiles]   $SourceFileSizeStr -> $OutputSizeStr    ($CompressionRatioStr)    Time: $FileDurationStr    Speed: $ProcessingSpeedStr`n")

# ==============================================================================
    # CYCLE END CLEANUP IN Z:\WORK AND FAILURES FOLDER IF EMPTY
    # ==============================================================================
    Remove-Item -LiteralPath $TempSourcePath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$VirtualWorkDir\*" -Recurse -Force -ErrorAction SilentlyContinue
  }
} while ($true)
 
Remove-Item -LiteralPath $VirtualWorkDir -Recurse -Force -ErrorAction SilentlyContinue

# Final line break to clear the console after the dynamic counter

Write-Host ""

# ==============================================================================
#  TOTALS AND END BLOCK
# ==============================================================================
$GlobalEndTime = Get-Date
$GlobalDuration = $GlobalEndTime - $GlobalStartTime
$GlobalDurationStr = $GlobalDuration.ToString("hh\:mm\:ss")

# Helper function to format gigabytes/megabytes in a human-readable format
function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } else {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
}

$TotalInitialSizeStr = Format-Bytes $TotalInitialBytes
$TotalFinalSizeStr = Format-Bytes $TotalFinalBytes

Write-Host "End: $GlobalEndTime"
Write-Host ""
$GlobalSizeDifference = $TotalFinalBytes -$TotalInitialBytes
if ($TotalInitialBytes -gt 0) {
    $GlobalCompressionRatio = [Math]::Round(($GlobalSizeDifference / $TotalInitialBytes) * 100) } else {$GlobalCompressionRatio = 0
}
$GlobalCompressionRatioStr = if ($GlobalCompressionRatio -ge 0) { "+$GlobalCompressionRatio%" } else { "$GlobalCompressionRatio%" }
$GlobalSpeedStr = if ($GlobalDuration.TotalSeconds -gt 0) { $sg = $TotalInitialBytes / $GlobalDuration.TotalSeconds; "$([Math]::Round($sg / 1MB, 2)) MB/s" } else { "0 MB/s" }

Add-Content -Path $ReportPath -Value "__________" -Encoding utf8

Add-Content -Path $ReportPath -Value "TOTALS:  $TotalInitialSizeStr -> $TotalFinalSizeStr    ($GlobalCompressionRatioStr)    Time: $GlobalDurationStr    Speed:$GlobalSpeedStr" -Encoding utf8

Write-Host "    TOTALS:      $TotalInitialSizeStr -> $TotalFinalSizeStr    ($GlobalCompressionRatioStr)    Time: $GlobalDurationStr    Speed:$GlobalSpeedStr" 
Write-Host ""
