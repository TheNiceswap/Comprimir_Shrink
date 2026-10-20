@echo off
openfiles >nul 2>&1
if %errorlevel% NEQ 0 ( powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs" &  exit /B  )
reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 0 /f >nul

cd /d "%~dp0"

:: Carga todas las variables desde config.txt
if not exist "config.txt" (echo Error: config.txt no encontrado & pause & exit /b) else (
   for /f "usebackq delims=" %%x in ("config.txt") do call %%x)


if exist %RutaTrabajoBase%\ (  echo La unidad %RutaTrabajoBase% ya existe. Saltando creacion... & goto :Seguir )
for /f %%a in ('powershell -NoProfile -Command "[Math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) - %MARGIN%"')  do set "RAM=%%a"

   if %RAM% LSS %MIN_Z% (
        echo [ERROR] La RAM segura calculada %RAM% GB es inferior al minimo de %MIN_Z% GB
        echo No es viable usar %RutaTrabajoBase%\ de forma segura. Cancelando operacion...
        timeout /t 1 /nobreak >nul 2>&1
        exit /b
   )

echo Creando disco RAM de %RAM% GB... 
cd /d "%~dp0others"
.\imdisk.exe  -a -t vm -s -%MARGIN%G -S 2048 -m %RutaTrabajoBase% -p "/fs:ntfs /a:2048 /q /y" >nul 2>nul || ( 
   sc create imdisk type= kernel start= demand binPath= "%~dp0others\imdisk.sys" DisplayName= "ImDisk Portable" >nul 2>nul
   sc start imdisk  >nul 2>nul
   timeout /t 1 /nobreak >nul 2>&1
   .\imdisk.exe  -a -t vm -s -%MARGIN%G -S 2048 -m %RutaTrabajoBase% -p "/fs:ntfs /a:2048 /q /y" >nul 2>nul 
)
cd ..

:Seguir

set "InstanciasRestantes=1"

:BucleCarpetas
set "CarpetaActual=%RutaTrabajoBase%\Trabajo%InstanciasRestantes%"
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Comprimir.ps1" -RutaEntrada "%RutaEntrada%" -RutaSalida "%RutaSalida%" -RutaInforme "%Informe%" -RutaTrabajoBase "%RutaTrabajoBase%"


set "OtrasInstanciasActivas=0"
set "ContadorTest=1"

:BucleFinal
if %ContadorTest% EQU %InstanciasRestantes%  ( set /a ContadorTest+=1 & goto BucleFinal )
set "CarpetaTest=%RutaTrabajoBase%\Trabajo%ContadorTest%"
if not exist "%CarpetaTest%" goto VerificarResultadoFinal
dir /a /b "%CarpetaTest%" 2>nul | findstr "^" >nul
if %errorlevel% EQU 0   ( set "OtrasInstanciasActivas=1" &  goto VerificarResultadoFinal )
set /a ContadorTest+=1
goto BucleFinal

:VerificarResultadoFinal

rmdir "%RutaEntrada%\Error" >nul 2>&1

if %OtrasInstanciasActivas% GTR 0 (
    echo  =======================================================================
    echo Otra instancia sigue procesando videos.
    echo  ======================================================================= 
    echo Cerrando esta ventana...
    echo  =======================================================================
    timeout /t 60
    exit /B
)

::  Si es 0, somos la última ventana activa
"%~dp0others\imdisk.exe" -D -m %RutaTrabajoBase%\  >nul 2>&1

if not exist "C:\Windows\System32\imdisk.cpl" (
    choice /c sn /d n /t 10 /m "¿Deseas eliminar IMDISK del SO?"
    if %errorlevel%==1 (
     schtasks /create /tn "WinDriverCleanup" /tr "cmd.exe /c del /f /q %WinDir%\System32\drivers\imdisk.sys & schtasks /delete /tn WinDriverCleanup /f" /sc onstart /ru "SYSTEM" /f >nul 2>&1   
     echo  Eliminamos  IMDISK en el próximo reinicio ...
     echo  .
    )
)

echo .
echo =======================================================================
echo   El procesamiento ha terminado. El PC hibernará/se apagara en 5 minutos 
echo   CIERRA ESTA VENTANA PARA ANULAR EL APAGADO     ( 'X' )
echo =======================================================================
echo.

::  reg add "HKCU\Console" /v "QuickEdit" /t REG_DWORD /d 1 /f >nul

timeout /t 300
shutdown /h >nul 2>&1 || shutdown /s /f /t 0
exit /B

