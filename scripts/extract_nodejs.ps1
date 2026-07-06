Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = 'E:\md3Music\md3Music\kugou_api_server\nodejs-mobile-v18.20.4-android.zip'
$jniLibsDir = 'E:\md3Music\md3Music\android\app\src\main\jniLibs\arm64-v8a'
$includeDir = 'E:\md3Music\md3Music\android\app\src\main\cpp\include\node'

$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)

# Extract libnode.so
$entry = $zip.Entries | Where-Object { $_.FullName -eq 'bin/arm64-v8a/libnode.so' }
if ($entry) {
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, "$jniLibsDir\libnode.so", $true)
    Write-Output "Extracted libnode.so ($([math]::Round($entry.Length/1MB, 1)) MB)"
}

# Extract include/node/ headers
$headers = $zip.Entries | Where-Object { $_.FullName -like 'include/node/*' -and -not $_.FullName.EndsWith('/') }
foreach ($h in $headers) {
    $relativePath = $h.FullName -replace '^include/node/', ''
    $targetDir = Split-Path "$includeDir\$relativePath" -Parent
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($h, "$includeDir\$relativePath", $true)
}
Write-Output "Extracted $($headers.Count) header files"

$zip.Dispose()
Write-Output "Done!"
