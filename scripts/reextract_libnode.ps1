Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = 'E:\md3Music\md3Music\kugou_api_server\nodejs-mobile-v18.20.4-android.zip'
$destDir = 'E:\md3Music\md3Music\android\app\src\main\jniLibs\arm64-v8a'
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$entry = $zip.Entries | Where-Object { $_.FullName -eq 'bin/arm64-v8a/libnode.so' }
Write-Output "Zip entry compressed size: $($entry.CompressedLength) bytes"
Write-Output "Zip entry uncompressed size: $($entry.Length) bytes"
$destFile = Join-Path $destDir 'libnode.so'
[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destFile, $true)
$destSize = (Get-Item $destFile).Length
Write-Output "Extracted file size: $destSize bytes"
$zip.Dispose()
