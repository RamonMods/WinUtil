#===========================================================================
# Testes - Tudo que altera o sistema passa pela camada de trabalhos

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:functionRoot = Join-Path $script:repoRoot "functions"
    $script:configRoot = Join-Path $script:repoRoot "config"
}

Describe "Roteamento de trabalho" {
    It "nunca entrega trabalho a uma janela de console própria" {
        # Um console separado tira o trabalho da camada de trabalhos, então ele não tem barra de progresso,
        # nem estado na barra de tarefas, nem linhas de log, e a janela sobrevive ao WinUtil
        $offenders = @()
        foreach ($file in (Get-ChildItem -Path $script:functionRoot -Filter *.ps1 -Recurse)) {
            $text = Get-Content -Path $file.FullName -Raw
            foreach ($line in ($text -split "`r?`n")) {
                if ($line -match '^\s*#') { continue }
                if ($line -match 'wt\s+new-tab') { $offenders += "$($file.Name): $($line.Trim())" }
                if ($line -match 'Start-Process\s+.*(powershell|pwsh)\.exe' -and $line -notmatch '-NoNewWindow') {
                    $offenders += "$($file.Name): $($line.Trim())"
                }
            }
        }

        if ($offenders.Count -gt 0) { throw ($offenders -join "`n") }
    }





    It "verifica comandos opcionais sem gerar erro quando estão ausentes" {
        $offenders = @()
        foreach ($file in (Get-ChildItem -Path $script:functionRoot -Filter *.ps1 -Recurse)) {
            $text = Get-Content -Path $file.FullName -Raw
            foreach ($line in ($text -split "`r?`n")) {
                if ($line -match 'if\s*\(\s*-not\s*\(Get-Command\s+[^\)]+\)\s*\)' -and $line -notmatch 'ErrorAction') {
                    $offenders += "$($file.Name): $($line.Trim())"
                }
            }
        }

        if ($offenders.Count -gt 0) { throw ($offenders -join "`n") }
    }





    It "nunca deixa o handle do runspace no pipeline" {
        # Invoke-WPFRunspace retorna um IAsyncResult. Uma chamada sem atribuição o imprime no
        # console, ou o incorpora ao que o fluxo de chamada retornar.
        $offenders = @()
        foreach ($file in (Get-ChildItem -Path $script:functionRoot -Filter *.ps1 -Recurse)) {
            if ($file.Name -eq "Invoke-WPFRunspace.ps1") { continue }
            foreach ($line in ((Get-Content -Path $file.FullName -Raw) -split "`r?`n")) {
                if ($line -match '^\s*Invoke-WPFRunspace\b') { $offenders += "$($file.Name): $($line.Trim())" }
            }
        }

        if ($offenders.Count -gt 0) { throw ($offenders -join "`n") }
    }






}
