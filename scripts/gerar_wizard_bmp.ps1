# ============================================================================
# Gerar imagens BMP para o instalador Inno Setup
# ============================================================================
# Gera duas imagens:
#   - wizard.bmp (164x314) - imagem grande da página de boas-vindas
#   - wizard_small.bmp (55x55) - ícone pequeno do topo
# ============================================================================

Add-Type -AssemblyName System.Drawing

$projectRoot = "C:\Users\charles\.antigravity\sistema_exodo_15-04-2026"
$outputDir = Join-Path $projectRoot "assets"

# Cores do tema Êxodo (laranja/dourado)
$bgDark = [Drawing.Color]::FromArgb(15, 23, 42)     # Azul escuro profundo
$bgMedium = [Drawing.Color]::FromArgb(30, 41, 59)   # Azul médio
$accentGold = [Drawing.Color]::FromArgb(255, 170, 50)  # Dourado Êxodo
$accentOrange = [Drawing.Color]::FromArgb(255, 140, 30) # Laranja
$white = [Drawing.Color]::White

# ============================================================================
# 1. Wizard BMP Grande (164x314) - Lateral da página de boas-vindas
# ============================================================================
Write-Host "Gerando wizard.bmp (164x314)..."

$wizardBmp = New-Object System.Drawing.Bitmap(164, 314)
$g = [System.Drawing.Graphics]::FromImage($wizardBmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

# Fundo com gradiente
for ($y = 0; $y -lt 314; $y++) {
    $ratio = $y / 314
    $r = [int]($bgDark.R * (1 - $ratio) + $bgMedium.R * $ratio)
    $g2 = [int]($bgDark.G * (1 - $ratio) + $bgMedium.G * $ratio)
    $b = [int]($bgDark.B * (1 - $ratio) + $bgMedium.B * $ratio)
    $color = [Drawing.Color]::FromArgb($r, $g2, $b)
    $pen = New-Object System.Drawing.Pen($color)
    $g.DrawLine($pen, 0, $y, 163, $y)
    $pen.Dispose()
}

# Orb decorativo no topo
$orbBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush(
    (New-Object System.Drawing.Drawing2D.GraphicsPath)
)
$orbBrush.CenterColor = [Drawing.Color]::FromArgb(30, 255, 170, 50)
$orbBrush.SurroundColors = @([Drawing.Color]::FromArgb(0, 15, 23, 42))
$g.FillEllipse($orbBrush, -50, -50, 200, 200)
$orbBrush.Dispose()

# Texto "ÊXODO" vertical
$fontLogo = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$brushGold = New-Object System.Drawing.SolidBrush($accentGold)

# Desenhar texto rotacionado
$g.TranslateTransform(82, 157)
$g.RotateTransform(-90)
$formatCenter = New-Object System.Drawing.StringFormat
$formatCenter.Alignment = [System.Drawing.StringAlignment]::Center
$formatCenter.LineAlignment = [System.Drawing.StringAlignment]::Center
$g.DrawString("EXODO", $fontLogo, $brushGold, 0, 0, $formatCenter)
$g.ResetTransform()

$fontLogo.Dispose()
$brushGold.Dispose()

# Linha decorativa sutil
$linePen = New-Object System.Drawing.Pen([Drawing.Color]::FromArgb(60, 255, 170, 50))
$linePen.Width = 1
$g.DrawLine($linePen, 30, 260, 134, 260)
$linePen.Dispose()

# Texto "SISTEMA" pequeno
$fontSmall = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
$brushWhite = New-Object System.Drawing.SolidBrush([Drawing.Color]::FromArgb(100, 255, 255, 255))
$g.DrawString("GESTAO INTELIGENTE", $fontSmall, $brushWhite, 82, 272, $formatCenter)
$fontSmall.Dispose()
$brushWhite.Dispose()

$g.Dispose()
$wizardBmp.Save((Join-Path $outputDir "wizard.bmp"), [System.Drawing.Imaging.ImageFormat]::Bmp)
$wizardBmp.Dispose()
Write-Host "  ✅ wizard.bmp criado em $outputDir"

# ============================================================================
# 2. Wizard Small BMP (55x55) - Ícone do topo
# ============================================================================
Write-Host "Gerando wizard_small.bmp (55x55)..."

$smallBmp = New-Object System.Drawing.Bitmap(55, 55)
$g2 = [System.Drawing.Graphics]::FromImage($smallBmp)
$g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

# Fundo escuro
$g2.Clear($bgDark)

# Círculo dourado
$circleBrush = New-Object System.Drawing.SolidBrush($accentGold)
$g2.FillEllipse($circleBrush, 8, 8, 39, 39)
$circleBrush.Dispose()

# Letra E dentro do círculo
$fontE = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$brushDark = New-Object System.Drawing.SolidBrush($bgDark)
$formatCenter2 = New-Object System.Drawing.StringFormat
$formatCenter2.Alignment = [System.Drawing.StringAlignment]::Center
$formatCenter2.LineAlignment = [System.Drawing.StringAlignment]::Center
$g2.DrawString("E", $fontE, $brushDark, 27, 28, $formatCenter2)
$fontE.Dispose()
$brushDark.Dispose()

$g2.Dispose()
$smallBmp.Save((Join-Path $outputDir "wizard_small.bmp"), [System.Drawing.Imaging.ImageFormat]::Bmp)
$smallBmp.Dispose()
Write-Host "  ✅ wizard_small.bmp criado em $outputDir"

Write-Host ""
Write-Host "============================================"
Write-Host "  IMAGENS GERADAS COM SUCESSO!"
Write-Host "============================================"
Write-Host "  - assets\wizard.bmp (164x314)"
Write-Host "  - assets\wizard_small.bmp (55x55)"
Write-Host "============================================"
