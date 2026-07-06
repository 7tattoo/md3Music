@echo off
echo ========================================
echo Building Node.js Server Bundle...
echo ========================================

cd /d "%~dp0..\kugou_api_server"

echo [1/3] Installing npm dependencies...
call npm install --production
if %ERRORLEVEL% neq 0 (
    echo ERROR: npm install failed
    exit /b 1
)

echo [2/3] Bundling with esbuild...
call npx esbuild index.js --bundle --minify --outfile=server_bundle.js --platform=node --target=node18
if %ERRORLEVEL% neq 0 (
    echo ERROR: esbuild bundle failed
    exit /b 1
)

echo [3/3] Copying to Flutter assets...
if not exist "%~dp0..\assets\nodejs-project" mkdir "%~dp0..\assets\nodejs-project"
copy /Y server_bundle.js "%~dp0..\assets\nodejs-project\server_bundle.js"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Copy failed
    exit /b 1
)

echo ========================================
echo Server bundle built successfully!
echo Output: assets\nodejs-project\server_bundle.js
echo ========================================
