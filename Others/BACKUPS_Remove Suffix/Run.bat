@echo off
openfiles >nul 2>&1
if %errorlevel% NEQ 0   powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs" &  exit /B

cd /d "%~dp0"

::  Load all variables from config.txt
if not exist "config.txt" (echo Error: config.txt not found & pause & exit /b) else (
   for /f "usebackq delims=" %%x in ("config.txt") do call %%x)

reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 0 /f >nul

if exist Z:\ (  echo Drive Z: already exists. Skipping creation... & goto :Seguir )
for /f %%a in ('powershell -NoProfile -Command "[Math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) - %MARGIN%"')  do set "RAM=%%a"

   if %RAM% LSS %MIN_Z% (
        echo [ERROR] The calculated safe RAM %RAM% GB is lower than the minimum of %MIN_Z% GB
        echo It is not viable to use Z:\ safely. Canceling operation...

        pause
        exit /b
   )
    echo Creating RAM disk of %RAM% GB...
    imdisk -a -t vm -s %RAM%G -m Z: >nul
    timeout /t 2 /nobreak >nul
    format.com Z: /fs:ntfs /a:2048 /q /y >nul

:Seguir

set "InstanciasRestantes=1"

:BucleCarpetas
set "CarpetaActual=%RutaTrabajoBase%Trabajo%InstanciasRestantes%"
if not exist "%CarpetaActual%" goto InstanciaEncontrada
dir /a /b "%CarpetaActual%" 2>nul | findstr "^" >nul
if %errorlevel% EQU 1  goto InstanciaEncontrada
set /a InstanciasRestantes+=1
goto BucleCarpetas


:InstanciaEncontrada
if not exist "%CarpetaActual%" mkdir "%CarpetaActual%"
if not exist "%RutaEntrada%\ERROR" mkdir "%RutaEntrada%\ERROR"

for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'dd-MM-yyyy'"`) do set "FECHA=%%i"
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'HH-mm'"`) do set "HORA=%%i"


set "Informe=%RutaInforme%\Informe%InstanciasRestantes%_%FECHA%_%HORA%.txt"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Shrink.ps1" -RutaEntrada "%RutaEntrada%" -RutaSalida "%RutaSalida%" -RutaInforme "%Informe%"


set "OtrasInstanciasActivas=0"
set "ContadorTest=1"

:BucleFinal
if %ContadorTest% EQU %InstanciasRestantes%  ( set /a ContadorTest+=1 & goto BucleFinal )
set "CarpetaTest=%RutaTrabajoBase%Trabajo%ContadorTest%"
if not exist "%CarpetaTest%" goto VerificarResultadoFinal
dir /a /b "%CarpetaTest%" 2>nul | findstr "^" >nul
if %errorlevel% EQU 0   ( set "OtrasInstanciasActivas=1" &  goto VerificarResultadoFinal )
set /a ContadorTest+=1
goto BucleFinal

:VerificarResultadoFinal

rmdir "%RutaEntrada%\Error" >nul 2>&1

if %OtrasInstanciasActivas% GTR 0 (
    echo  =======================================================================
    echo Another instance is still processing videos.
    echo  ======================================================================= 
    echo Closing this window...
    echo  =======================================================================
    timeout /t 120
    exit /B
)

::  Si es 0, somos la última ventana activa
echo =======================================================================
echo   Processing has finished. The PC will shut down in 5 minutes.
echo   CLOSE THIS WINDOW TO CANCEL THE SHUTDOWN.
echo =======================================================================
echo.

::  reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 1 /f >nul

timeout /t 300
shutdown /s /f /t 0
