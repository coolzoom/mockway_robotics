# Fix CRLF -> LF for WSL/Linux shell scripts under tools/
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Get-ChildItem -Path $root -Recurse -Filter '*.sh' | ForEach-Object {
    $c = [IO.File]::ReadAllText($_.FullName)
    $c = $c -replace "`r`n", "`n" -replace "`r", ""
    if (-not $c.EndsWith("`n")) { $c += "`n" }
    [IO.File]::WriteAllText($_.FullName, $c, (New-Object Text.UTF8Encoding $false))
    Write-Host "LF: $($_.Name)"
}
Write-Host "Done."
