$uri = "http://127.0.0.1:8080/login/qr/key?timestamp=1783180000"
try {
    $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Output "Status: $($r.StatusCode)"
    Write-Output "Body: $($r.Content)"
} catch {
    Write-Output "Error: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        Write-Output "Body: $($reader.ReadToEnd())"
    }
}

Write-Output "`n=== Album Detail ==="
$uri2 = "http://127.0.0.1:8080/album/detail?album_id=197015691"
try {
    $r2 = Invoke-WebRequest -Uri $uri2 -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Output "Status: $($r2.StatusCode)"
    Write-Output "Body: $($r2.Content.Substring(0, [Math]::Min(500, $r2.Content.Length)))"
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}

Write-Output "`n=== Playlist Detail ==="
$uri3 = "http://127.0.0.1:8080/playlist/detail?specialid=12345"
try {
    $r3 = Invoke-WebRequest -Uri $uri3 -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Output "Status: $($r3.StatusCode)"
    Write-Output "Body: $($r3.Content.Substring(0, [Math]::Min(500, $r3.Content.Length)))"
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
