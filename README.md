# Compresor de Vídeo con FFmpeg, ImDisk y PowerShell / Video Compressor with FFmpeg, ImDisk, and PowerShell

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| Este proyecto automatiza la compresión masiva de vídeos a formato H.265 (HEVC) utilizando **FFmpeg** e **ImDisk** a través de instancias temporales en memoria RAM (unidad Z:), optimizando el rendimiento y protegiendo la vida útil de tus unidades SSD. | This project automates the bulk compression of videos to H.265 (HEVC) format using **FFmpeg** and **ImDisk** through temporary instances in RAM (Z: drive), optimizing performance and protecting your SSD lifespan. |

## 🛠️ Requisitos / Requirements

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| * Windows 10/11 (Ejecutado como Administrador para la gestión del RAMDisk). | * Windows 10/11 (Executed as Administrator for RAMDisk management). |
| * Tarjeta gráfica compatible con codificación por hardware NVIDIA (`hevc_nvenc`). | * Graphics card compatible with NVIDIA hardware encoding (`hevc_nvenc`). |
| * Herramienta **ImDisk** (Opcional): Necesaria para montar el disco virtual en RAM. Si no está instalada, el script se ejecutará directamente en el almacenamiento local. | * **ImDisk** tool (Optional): Required to mount the virtual RAM disk. If not installed, the script will run directly on local storage. |

## 📂 Estructura y Selección de Idioma / Structure & Language Selection

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| El repositorio incluye versiones independientes para español e inglés. Por defecto, la raíz está configurada en español. | The repository includes independent versions for Spanish and English. By default, the root directory is configured in Spanish. |
| * **`/` (Raíz):** Contiene los archivos por defecto en español (`Haz.bat` y `Shrink.ps1`). | * **`/` (Root):** Contains the default files in Spanish (`Haz.bat` and `Shrink.ps1`). |
| * **`/Others/`:** Contiene los binarios (`ffmpeg.exe`, `ffprobe.exe`). | * **`/Others/`:** Contains the binaries (`ffmpeg.exe`, `ffprobe.exe`). |
| * **`/Others/BACKUPS_Remove Suffix/`:** Contiene los scripts preparados para cada idioma (`Comprimir.ps1`, `Comprimir_spa.ps1`, `Haz.bat`, `Haz_spa.bat`, `Run.bat`, `Run_eng.bat`, `Shrink.ps1`, `Shrink_eng.ps1`). | * **`/Others/BACKUPS_Remove Suffix/`:** Contains the pre-configured scripts for each language (`Comprimir.ps1`, `Comprimir_spa.ps1`, `Haz.bat`, `Haz_spa.bat`, `Run.bat`, `Run_eng.bat`, `Shrink.ps1`, `Shrink_eng.ps1`). |

## 🚀 Uso / Usage

| 🇪🇸 Versión en Español (Por defecto) | 🇬🇧 English Version |
| :--- | :--- |
| Configura tus rutas de carpetas editando el archivo `Haz.bat` en la raíz del proyecto y ejecútalo. El sistema procesará los vídeos en paralelo de manera automática. | To use the English version, copy `Run_eng.bat` and `Shrink_eng.ps1` from the `Others` folder into the root directory. Configure your folder paths inside `Run_eng.bat` and execute it. |

---

⚠️ **Información Crítica / Critical Information:**

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| 🛑 Al finalizar el procesamiento de todos los vídeos, la última ventana activa programará un **apagado automático del ordenador** tras una cuenta atrás de 5 minutos. | 🛑 Upon completing the execution of the entire video list, the last active window will schedule an **automatic PC shutdown** after a 5-minute countdown. |
| ❌ La **única manera de evitar o cancelar** los contadores de tiempo (tanto los *timeouts* como el apagado final) es **cerrar por completo la ventana de la consola pulsando la 'X'** de Windows. | ❌ The **only way to avoid or cancel** the countdown timers (both regular timeouts and the final shutdown) is to **completely close the console window by clicking the Windows 'X' button**. |
| 📊 Al terminar el proceso, el programa **genera automáticamente un archivo de informe de texto (.txt)** con el desglose detallado de todos los archivos procesados, tamaños finales y velocidades. | 📊 Once the process finishes, the program **automatically generates a text report file (.txt)** with a detailed breakdown of all processed files, final sizes, and speeds. |
