@echo off
echo ========================================
echo Building Node.js Server Bundle...
echo ========================================

cd /d "%~dp0.."

echo [1/3] Generating bundled entry (static module requires)...
call node scripts\gen_node_bundle_entry.js
if %ERRORLEVEL% neq 0 (
    echo ERROR: generate entry failed
    exit /b 1
)

cd /d "%~dp0..\kugou_api_server"

echo [2/3] Bundling with esbuild (entry: bundled_entry.js)...
if not exist node_modules\.bin\esbuild call npm install --production
call npx esbuild bundled_entry.js --bundle --minify --outfile=server_bundle.js --platform=node --target=node18
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
