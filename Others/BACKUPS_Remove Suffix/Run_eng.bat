@echo off
openfiles >nul 2>&1
if %errorlevel% NEQ 0   powershell -Command "Start-Process -FilePath '%0' -Verb RunAs" &  exit /B

cd /d "%~dp0"

:: Load all variables from config.txt
if not exist "config.txt" (echo Error: config.txt not found & pause & exit /b) else (
   for /f "usebackq delims=" %%x in ("config.txt") do call %%x)

reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 0 /f >nul

if exist Z:\ (  echo Drive Z: already exists. Skipping creation... & goto :Follow )
for /f %%a in ('powershell -NoProfile -Command "[Math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) - %MARGIN%"')  do set "RAM=%%a"

   if %RAM% LSS %MIN_Z% (
        echo [ERROR] The calculated safe RAM (%RAM% GB) is lower than the minimum of %MIN_Z% GB.
        echo It is not viable to use Z:\ safely. Canceling operation...
        pause
        exit /b
   )
    echo Creating RAM disk of %RAM% GB...
    imdisk -a -t vm -s %RAM%G -m Z: >nul
    timeout /t 2 /nobreak >nul
    format.com Z: /fs:ntfs /a:2048 /q /y >nul

:Follow

set "RemainingInstances=1"

:FolderLoop
set "CurrentFolder=%BaseWorkPath%Work%RemainingInstances%"
if not exist "%CurrentFolder%" goto InstanceFound
dir /a /b "%CurrentFolder%" 2>nul | findstr "^" >nul
if %errorlevel% EQU 1  goto InstanceFound
set /a RemainingInstances+=1
goto FolderLoop


:InstanceFound
if not exist "%CurrentFolder%" mkdir "%CurrentFolder%"
if not exist "%InputPath%\Failures" mkdir "%InputPath%\Failures"


for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'dd-MM-yyyy'"`) do set "DATE=%%i"
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'HH-mm'"`) do set "TIME=%%i"


set "Report=%ReportPath%\Report%RemainingInstances%_%DATE%_%TIME%.txt"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Shrink.ps1" -InputPath "%InputPath%" -CustomOutputPath "%OutputPath%" -ReportPath "%Report%"



set "OtherActiveInstances=0"
set "TestCounter=1"

:FinalLoop
if %TestCounter% EQU %RemainingInstances% ( set /a TestCounter+=1 & goto FinalLoop )
set "TestFolder=%BaseWorkPath%Work%TestCounter%"
if not exist "%TestFolder%" goto VerifyFinalResult
dir /a /b "%TestFolder%" 2>nul | findstr "^" >nul
if %errorlevel% EQU 0   ( set "OtherActiveInstances=1" &  goto VerifyFinalResult )
set /a TestCounter+=1
goto FinalLoop

:VerifyFinalResult

rmdir "%InputPath%\Failures" >nul 2>&1

if %OtherActiveInstances% GTR 0 (
    echo  =======================================================================
    echo Another instance is still processing videos.
    echo  ======================================================================= 
    echo Closing this window...
    echo  =======================================================================
    timeout /t 120
    exit /B
)

::  If 0, we are the last active window
echo =======================================================================
echo   Processing has finished. The PC will shut down in 5 minutes.
echo   CLOSE THIS WINDOW TO CANCEL THE SHUTDOWN.
echo =======================================================================
echo.

::  reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 1 /f >nul

timeout /t 300
shutdown /s /f /t 0
