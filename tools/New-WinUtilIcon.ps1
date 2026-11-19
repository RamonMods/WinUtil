<#
    .SYNOPSIS
        Adiciona ou substitui o ícone de um aplicativo em config/icons

    .DESCRIPTION
        Redimensiona uma imagem (PNG, ICO, JPG, GIF ou BMP) para caber em uma tela transparente de 48x48 e a salva
        como config/icons/<Key>.png, em que Key é a chave do aplicativo em config/applications.json. O arquivo
        é incorporado ao script quando ele é compilado. Um aplicativo sem arquivo de ícone usa como fallback
        o favicon do seu site.

    .EXAMPLE
        .\tools\New-WinUtilIcon.ps1 -Key brave -Path C:\Downloads\brave.png
#>
param(
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][string]$Path
)

Add-Type -AssemblyName System.Drawing

$size = 48
$margin = 0.04
$configRoot = Join-Path $PSScriptRoot "..\config"
$applications = Get-Content (Join-Path $configRoot "applications.json") -Raw | ConvertFrom-Json
$application = $applications.PSObject.Properties[$Key]
if (-not $application) { throw "'$Key' não é uma chave em config/applications.json." }
$Key = $application.Name

# Lê o arquivo na memória, para que um ícone existente possa ser usado como própria entrada sem ficar bloqueado
$sourceStream = [IO.MemoryStream]::new([IO.File]::ReadAllBytes((Resolve-Path $Path)))
$source = [Drawing.Image]::FromStream($sourceStream)
$canvas = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = $null
try {
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $fit = $size * (1 - 2 * $margin) / [Math]::Max($source.Width, $source.Height)
    $width = [int][Math]::Round($source.Width * $fit)
    $height = [int][Math]::Round($source.Height * $fit)
    $graphics.DrawImage($source, [int](($size - $width) / 2), [int](($size - $height) / 2), $width, $height)

    $iconsFolder = Join-Path $configRoot "icons"
    $null = New-Item -ItemType Directory -Path $iconsFolder -Force
    $target = Join-Path (Resolve-Path $iconsFolder) "$Key.png"
    $canvas.Save($target, [Drawing.Imaging.ImageFormat]::Png)
} finally {
    if ($graphics) { $graphics.Dispose() }
    $source.Dispose(); $sourceStream.Dispose(); $canvas.Dispose()
}

Write-Host "Salvo um ícone de $size x $size para '$Key' ($((Get-Item $target).Length) bytes) em config/icons/$Key.png."
