Set-Location 'c:\zinzi2\zinzi2\lib'
Get-ChildItem -Path . -Filter "*.dart" -Recurse | ForEach-Object {
    Write-Host "Processing $($_.FullName)"
    $content = Get-Content $_.FullName
    $newContent = $content -replace "('\[)([A-Z][a-zA-Z]*)('\])", { param($match) "'$($match.Groups[1])$($match.Groups[2].ToLower())$($match.Groups[3])'" }
    Set-Content -Path $_.FullName -Value $newContent
}
Write-Host "Lowercase conversion complete."