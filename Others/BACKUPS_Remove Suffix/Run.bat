@echo off
openfiles >nul 2>&1
if %errorlevel% NEQ 0   powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs" &  exit /B
reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 0 /f >nul

cd /d "%~dp0"

::  Load all variables from config.txt
if not exist "config.txt" (echo Error: config.txt not found & pause & exit /b) else (
   for /f "usebackq delims=" %%x in ("config.txt") do call %%x)


if exist Z:\ (  echo Drive Z: already exists. Skipping creation...  & goto :Follow )
for /f %%a in ('powershell -NoProfile -Command "[Math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) - %MARGIN%"')  do set "RAM=%%a"

   if %RAM% LSS %MIN_Z% (
        echo [ERROR] The calculated safe RAM %RAM% GB is lower than the minimum of %MIN_Z% GB
        echo It is not viable to use Z:\ safely. Canceling operation...
        pause
        exit /b
   )
    echo  Creating RAM disk of  %RAM% GB...
   cd /d "%~dp0others"
.\imdisk.exe  -a -t vm -s -%MARGIN%G -S 2048 -m Z: -p "/fs:ntfs /q /y" >nul 2>nul || (    
   sc create imdisk.exe type= kernel start= demand binPath= "%~dp0others\imdisk.sys" DisplayName= "ImDisk Portable" >nul 2>nul 
   sc start imdisk.exe  >nul 2>nul
   .\imdisk.exe  -a -t vm -s -%MARGIN%G -S 2048 -m Z: -p "/fs:ntfs /q /y" >nul 2>nul 
)
cd ..

:Follow

set "RemainingInstances=1"

:Follow_0
set "CurrentInstancePath=%BaseWorkPath%Trabajo%RemainingInstances%"
if not exist "%CurrentInstancePath%" goto Follow_1
dir /a /b "%CurrentInstancePath%" 2>nul | findstr "^" >nul
if %errorlevel% EQU 1  goto Follow_1
set /a RemainingInstances+=1
goto Follow_0


:Follow_1
if not exist "%CurrentInstancePath%" mkdir "%CurrentInstancePath%"
if not exist "%InputPath%\ERROR" mkdir "%InputPath%\ERROR"

for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'dd-MM-yyyy'"`) do set "CurrentDate=%%i"
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'HH-mm'"`) do set "CurrentTime=%%i"


set "FullReportFilePath=%ReportPath%\FullReportFilePath%RemainingInstances%_%CurrentDate%_%CurrentTime%.txt"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Shrink.ps1" -InputPath "%InputPath%" -OutputPath "%OutputPath%" -ReportPath "%FullReportFilePath%"


set "ActiveInstancesFound=0"
set "CheckInstanceIndex=1"

:Follow_2
if %CheckInstanceIndex% EQU %RemainingInstances%  ( set /a CheckInstanceIndex+=1 & goto Follow_2 )
set "CheckInstancePath=%BaseWorkPath%Trabajo%CheckInstanceIndex%"
if not exist "%CheckInstancePath%" goto Follow_3
dir /a /b "%CheckInstancePath%" 2>nul | findstr "^" >nul
if %errorlevel% EQU 0   ( set "ActiveInstancesFound=1" &  goto Follow_3 )
set /a CheckInstanceIndex+=1
goto Follow_2

:Follow_3

rmdir "%InputPath%\Error" >nul 2>&1

if %ActiveInstancesFound% GTR 0 (
  echo  =======================================================================
    echo Another instance is still processing videos.
    echo  ======================================================================= 
    echo Closing this window...
    echo  =======================================================================
    timeout /t 120
    exit /B
)

::  If it's 0, we are the last active window.
"%~dp0others\imdisk.exe" -D -m Z:  >nul 2>&1
timeout /t 1 /nobreak  >nul 2>&1
sc stop imdisk >nul 2>&1
timeout /t 1 /nobreak >nul 2>&1
sc delete imdisk  >nul 2>&1 
timeout /t 1 /nobreak >nul 2>&1
del /f /q "%WinDir%\System32\drivers\imdisk.sys" >nul 2>&1

echo =======================================================================
echo   Processing has finished. The PC will shut down in 5 minutes.
echo   CLOSE THIS WINDOW TO CANCEL THE SHUTDOWN.
echo =======================================================================
echo.

::  reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 1 /f >nul

timeout /t 300
shutdown /h >nul 2>&1 || shutdown /s /f /t 0
exit /B
