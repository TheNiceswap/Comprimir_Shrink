# Compresor de Vídeo con FFmpeg, ImDisk y PowerShell / Video Compressor with FFmpeg, ImDisk, and PowerShell

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| Este proyecto automatiza la compresión masiva de vídeos a formato H.265 (HEVC) utilizando **FFmpeg** e **ImDisk** a través de instancias temporales en memoria RAM (unidad Z:), optimizando el rendimiento y protegiendo la vida útil de tus unidades SSD. | This project automates the bulk compression of videos to H.265 (HEVC) format using **FFmpeg** and **ImDisk** through temporary instances in RAM (Z: drive), optimizing performance and protecting your SSD lifespan. |

## 🧠 Características Principales / Key Features

| 🇪🇸 Funcionalidades Clave | 🇬🇧 Key Features |
| :--- | :--- |
| **1. Instancias en paralelo**: Permite incorporar nuevos vídeos a la carpeta de entrada sobre la marcha y lanzar varios scripts que se gestionan en paralelo sin conflictos. | **1. Parallel Instances**: Allows adding new videos to the input folder on the fly and launching multiple concurrent scripts without conflicts. |
| **2. Protección contra caídas (`.tmp`)**: Si el PC se apaga inesperadamente, al reiniciar el sistema busca los archivos temporales y los restaura automáticamente a su estado original. | **2. Crash Protection (`.tmp`)**: If the PC shuts down unexpectedly, upon reboot the system scans for temporary files and automatically restores them to their original state. |
| **3. Evita la sobrescritura**: El sistema detecta si un archivo ya existe en la carpeta de destino y renombra los duplicados automáticamente para proteger tus datos originales. | **3. Overwrite Prevention**: The system detects if a file already exists in the destination folder and automatically renames duplicates to protect your original data. |
| **4. Optimización de tamaño e integridad**: Si el vídeo comprimido pesa más que el original, el script lo descarta y exporta el original. Además, mantiene el audio intacto sin pérdida de calidad. | **4. Size Optimization & Integrity**: If the compressed video ends up larger than the original, the script discards it and exports the original. It also keeps the audio intact with no quality loss. |
| **5. Gestión de archivos corruptos**: Si el sistema detecta un archivo que parece dañado o corrupto, lo aísla de forma segura moviéndolo a una carpeta llamada `ERROR` dentro de la propia carpeta de entrada. | **5. Corrupt File Handling**: If the system detects a file that appears to be damaged or corrupt, it safely isolates it by moving it to an `ERROR` folder inside the input directory. |
| **6. Informes automáticos**: Al finalizar el proceso, el programa genera un informe detallado en texto (`.txt`) con los tamaños finales, tiempos y velocidad de procesamiento. | **6. Automatic Reports**: Upon process completion, the program generates a detailed text report (`.txt`) with final sizes, processing times, and speed. |
| **7. 100% Portable**: No requiere instalación manual. El script gestiona de forma autónoma la elevación de privilegios, la inyección del driver del kernel (ImDisk) y los ajustes de consola necesarios en caliente, asegurando revertir y limpiar por completo el sistema al finalizar el proceso.| **7. 100% Portable**: Requires no manual installation. The script autonomously handles privilege elevation, kernel driver injection (ImDisk), and runtime console adjustments on the fly, ensuring it completely reverts and cleans the system upon completion.|
|**8. Eficiencia térmica (Bajas temperaturas)**: Al aislar las lecturas y escrituras masivas dentro del RAMDisk, se elimina la fricción constante en los discos físicos (SSDs/HDDs), manteniendo el sistema notablemente más fresco durante renders largos.|**8. Thermal Efficiency (Lower Temps)**: By isolating massive I/O operations inside the RAMDisk, it eliminates continuous friction on physical drives (SSDs/HDDs), keeping the system noticeably cooler during long rendering sessions.|


## 🛠️ Requisitos / Requirements

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| * **Windows 10/11**: El script gestiona de forma automática la elevación de privilegios de Administrador para la creación del RAMDisk. | * **Windows 10/11**: The script automatically handles Administrator privilege elevation for RAMDisk management. |
| * **Hardware**: Requiere tarjeta gráfica NVIDIA (`hevc_nvenc`). El script reescala automáticamente los vídeos a un máximo de 1080p (Full HD), manteniendo intactas aquellas resoluciones que ya sean menores. | * **Hardware**: Requires an NVIDIA graphics card (`hevc_nvenc`). The script automatically downscales videos to a maximum of 1080p (Full HD), keeping lower resolutions untouched. |
| * **RAM Mínima Asegurada**: El script calcula la RAM disponible. Si el espacio libre restante en tu sistema es inferior al mínimo fijado en `config.txt` (`MIN_Z`), el proceso se cancelará por seguridad. | * **Minimum Verified RAM**: The script calculates available RAM. If the remaining system memory is lower than the `MIN_Z` threshold in `config.txt`, the operation will abort to prevent system instability. |

## 📂 Estructura y Configuración / Structure & Configuration

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| * **`config.txt`**: ⚙️ Archivo único de configuración. Modifica aquí tus rutas y calidad. | * **`config.txt`**: ⚙️ Single configuration file. Modify your paths and quality settings here. |
| * **`Haz.bat`**: Ejecutable principal para lanzar el proceso en Español. | * **`Haz.bat`**: Main executable to launch the process in Spanish. |
| * **`Run.bat`**: Ejecutable principal para lanzar el proceso en Inglés. | * **`Run.bat`**: Main executable to launch the process in English. |
| * **`Comprimir.ps1` / `Shrink.ps1`**: Scripts internos de PowerShell. | * **`Comprimir.ps1` / `Shrink.ps1`**: Internal PowerShell scripts. |

## 🚀 Uso / Usage

| 🇪🇸 Versión en Español | 🇬🇧 English Version |
| :--- | :--- |
| Configura tus rutas de carpetas editando el archivo `config.txt` en la raíz del proyecto. Coloca tus vídeos en la carpeta de entrada y ejecuta `Haz.bat`. El sistema procesará los vídeos automáticamente. | Configure your folder paths by editing the `config.txt` file in the root directory. Place your videos in the input folder and execute `Run.bat`. The system will automatically process the videos. |

---

⚠️ **Información Crítica / Critical Information:**

| 🇪🇸 Español | 🇬🇧 English |
| :--- | :--- |
| 🛑 Al finalizar el procesamiento de todos los vídeos, la última ventana activa programará la **hibernación automática del ordenador** (o apagado si no está disponible) tras una cuenta atrás de 5 minutos. | 🛑 Upon completing the execution of the entire video list, the last active window will schedule an **automatic PC hibernation** (or shutdown if unavailable) after 5 minutes. |
| ❌ La **única manera de evitar o cancelar** los contadores de tiempo (tanto los *timeouts* como el apagado final) es **cerrar por completo la ventana de la consola pulsando la 'X'** de Windows. | ❌ The **only way to avoid or cancel** the countdown timers (both regular timeouts and the final shutdown) is to **completely close the console window by clicking the Windows 'X' button**. |
