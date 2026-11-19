#===========================================================================
# Testes - Agrupamento de logs do relatório de ambiente
#===========================================================================

BeforeAll {
    . (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "functions\private\Get-WinUtilRecentLogs.ps1")
}

Describe "Get-WinUtilRecentLogs" {
    BeforeEach {
        $script:logDir = Join-Path $TestDrive "logs"
        New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null

        $recentPath = Join-Path $script:logDir "winutil_2026-08-20_10-00-00.log"
        "recent session log" | Out-File -FilePath $recentPath -Encoding utf8
        (Get-Item $recentPath).LastWriteTime = (Get-Date).AddDays(-1)

        $oldPath = Join-Path $script:logDir "winutil_2026-07-01_10-00-00.log"
        "old session log" | Out-File -FilePath $oldPath -Encoding utf8
        (Get-Item $oldPath).LastWriteTime = (Get-Date).AddDays(-30)

        $unrelatedPath = Join-Path $script:logDir "notes.txt"
        "unrelated file" | Out-File -FilePath $unrelatedPath -Encoding utf8
        (Get-Item $unrelatedPath).LastWriteTime = (Get-Date).AddDays(-1)
    }

    It "inclui apenas arquivos winutil_*.log dentro da janela de dias" {
        $result = Get-WinUtilRecentLogs -Days 7 -LogDirectory $script:logDir

        $result | Should -Match "recent session log"
        $result | Should -Not -Match "old session log"
        $result | Should -Not -Match "unrelated file"
    }

    It "prefixa cada arquivo incluído com um cabeçalho que o identifica" {
        $result = Get-WinUtilRecentLogs -Days 7 -LogDirectory $script:logDir

        $result | Should -Match "=== winutil_2026-08-20_10-00-00\.log ==="
    }

    It "retorna uma string vazia quando o diretório de logs não existe" {
        $result = Get-WinUtilRecentLogs -Days 7 -LogDirectory (Join-Path $TestDrive "missing")

        $result | Should -BeNullOrEmpty
    }

    It "lê um diretório de logs exato cujo nome contém caracteres curinga" {
        $literalDirectory = Join-Path $TestDrive "logs[1]"
        [System.IO.Directory]::CreateDirectory($literalDirectory) | Out-Null
        $literalLog = Join-Path $literalDirectory "winutil_2026-08-20_11-00-00.log"
        "literal path session log" | Set-Content -LiteralPath $literalLog
        (Get-Item -LiteralPath $literalLog).LastWriteTime = (Get-Date).AddDays(-1)

        $result = Get-WinUtilRecentLogs -Days 7 -LogDirectory $literalDirectory

        $result | Should -Match "literal path session log"
    }

    It "falha no agrupamento quando o diretório de logs não pode ser enumerado" {
        Mock Get-ChildItem { throw "log directory access denied" }

        { Get-WinUtilRecentLogs -Days 7 -LogDirectory $script:logDir } |
            Should -Throw "*log directory access denied*"
    }

    It "falha no agrupamento quando um log selecionado desaparece antes de ser lido" {
        Mock Get-Content { throw "log disappeared" }

        { Get-WinUtilRecentLogs -Days 7 -LogDirectory $script:logDir } |
            Should -Throw "*log disappeared*"
    }
}
