@echo off
chcp 65001 > nul
REM ============================================================
REM  MD3Music -  Native Libraries Setup Script
REM  Downloads and extracts libnode.so + Node.js headers
REM  Usage: Run this script from the project root directory
REM ============================================================

setlocal EnableDelayedExpansion

REM --- Detect script location as project root ---
set PROJECT_ROOT=%~dp0
echo Project root: %PROJECT_ROOT%

REM --- Check if already installed ---
if exist "%PROJECT_ROOT%android\app\src\main\jniLibs\arm64-v8a\libnode.so" (
    echo [OK] libnode.so already exists, skipping download.
    echo Run `git clean -fdx` first if you want to reinstall.
    goto :eof
)

REM --- Download URL (latest release asset) ---
set DOWNLOAD_URL=https://github.com/zzyoxml/md3Music/releases/latest/download/native-libs.zip
set ZIP_FILE=%PROJECT_ROOT%native-libs.zip

echo.
echo [1/3] Downloading native-libs.zip from GitHub Releases...
echo URL: %DOWNLOAD_URL%
echo.

powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_FILE%' -ErrorAction Stop; Write-Host 'Download complete.' }"

if not exist "%ZIP_FILE%" (
    echo [ERROR] Download failed. Please check your internet connection.
    echo You can manually download from: %DOWNLOAD_URL%
    exit /b 1
)

REM --- Extract ZIP ---
echo.
echo [2/3] Extracting native-libs.zip...
powershell -Command "& { Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%PROJECT_ROOT%' -Force; Write-Host 'Extraction complete.' }"

if errorlevel 1 (
    echo [ERROR] Extraction failed.
    exit /b 1
)

REM --- Verify extraction ---
echo.
echo [3/3] Verifying installation...
set MISSING=0
if not exist "%PROJECT_ROOT%android\app\src\main\jniLibs\arm64-v8a\libnode.so" (
    echo [MISSING] arm64-v8a/libnode.so
    set /a MISSING+=1
)
if not exist "%PROJECT_ROOT%android\app\src\main\jniLibs\armeabi-v7a\libnode.so" (
    echo [MISSING] armeabi-v7a/libnode.so
    set /a MISSING+=1
)
if not exist "%PROJECT_ROOT%android\app\src\main\jniLibs\x86_64\libnode.so" (
    echo [MISSING] x86_64/libnode.so
    set /a MISSING+=1
)
if not exist "%PROJECT_ROOT%android\app\src\main\cpp\include\node\node.h" (
    echo [MISSING] Node.js headers
    set /a MISSING+=1
)

if %MISSING% GTR 0 (
    echo.
    echo [ERROR] Some files are missing after extraction.
    exit /b 1
)

REM --- Cleanup ---
del "%ZIP_FILE%" /Q
echo.
echo ============================================================
echo  Native libraries installed successfully!
echo  You can now run: flutter build apk --release --split-per-abi
echo ============================================================
exit /b 0
