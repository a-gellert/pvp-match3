Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\User\.gemini\antigravity\brain\0b69f11e-c06d-437e-a7fc-398011c49e7e\app_icon_dark_fantasy_match3_fullbleed_1794640254204.jpg"
if (-not (Test-Path $srcPath)) {
    Write-Error "Source file not found: $srcPath"
    exit 1
}

$src = [System.Drawing.Bitmap]::FromFile($srcPath)
Write-Host "Source size: $($src.Width)x$($src.Height)"

$dst = New-Object System.Drawing.Bitmap(800, 800, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$rect = New-Object System.Drawing.Rectangle(0, 0, 800, 800)
$g.DrawImage($src, $rect)

New-Item -ItemType Directory -Force -Path "promo" | Out-Null
$dst.Save("promo/icon_800x800.png", [System.Drawing.Imaging.ImageFormat]::Png)
$dst.Save("promo/gem_vanguard_square_800x800.png", [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose()
$dst.Dispose()
$src.Dispose()

Write-Host "Saved promo/icon_800x800.png and promo/gem_vanguard_square_800x800.png (800x800)"
