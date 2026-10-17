# 把 docs/icon.html 的三种外观导出成 App 图标：1024×1024、不带透明通道的 PNG。
# 在项目根目录用 PowerShell 运行：powershell -ExecutionPolicy Bypass -File docs/export-icon.ps1
# 本文件必须保存为带 BOM 的 UTF-8，否则 Windows PowerShell 5.1 会把中文读成乱码。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$source = 'file:///' + ("$PSScriptRoot\icon.html" -replace '\\', '/' -replace ' ', '%20')
$output = Join-Path $root 'App\Assets.xcassets\AppIcon.appiconset'
$temp = Join-Path $env:TEMP 'phonepulse-icon'
New-Item -ItemType Directory -Force $temp | Out-Null

$files = @{ light = 'AppIcon.png'; dark = 'AppIcon-dark.png'; tinted = 'AppIcon-tinted.png' }
foreach ($variant in 'light', 'dark', 'tinted') {
    $shot = Join-Path $temp "$variant.png"
    Remove-Item $shot -ErrorAction SilentlyContinue
    # Edge 是窗口程序，接上管道 PowerShell 才会等它截完图再往下走
    & $edge --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$temp\profile" --force-device-scale-factor=1 --window-size=1024,1024 --screenshot="$shot" "$source#$variant" | Out-Null
    if (-not (Test-Path $shot)) { throw "$variant 截图失败" }

    # App Store 不接受带透明通道的图标：重画到 24 位 RGB 画布上再保存
    $image = [System.Drawing.Image]::FromFile($shot)
    try {
        if ($image.Width -ne 1024 -or $image.Height -ne 1024) { throw "$variant 截图尺寸是 $($image.Width)×$($image.Height)，应为 1024×1024" }
        $bitmap = New-Object System.Drawing.Bitmap 1024, 1024, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.DrawImage($image, 0, 0, 1024, 1024)
        $graphics.Dispose()
        $target = Join-Path $output $files[$variant]
        $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        Write-Host "$variant -> $target"
    } finally {
        $image.Dispose()
    }
}
