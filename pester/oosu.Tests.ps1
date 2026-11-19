#===========================================================================
# Testes - Fluxo de download do O&O ShutUp10++
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    . (Join-Path $script:repoRoot "functions\private\Save-WinUtilFile.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFOOSU.ps1")

    function Invoke-WPFRunspace {
        param($ArgumentList, $ParameterList, [scriptblock]$ScriptBlock)
    }
    function Start-WinUtilJob {
        param([string]$Name, [scriptblock]$ScriptBlock, [hashtable]$Parameters, [string]$Description, [switch]$DisableAppList)
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }

    function script:New-WinUtilOOSUTestContext {
        param([bool]$ProcessRunning = $false)

        $script:sync = [Hashtable]::Synchronized(@{
            ProcessRunning = $ProcessRunning
            winutildir = $TestDrive
            Form = [pscustomobject]@{
                Dispatcher = [pscustomobject]@{}
            }
        })
    }
}

Describe "Save-WinUtilFile" {
    It "copia um download e informa sua porcentagem" {
        $sourcePath = Join-Path $TestDrive "source.bin"
        $destinationPath = Join-Path $TestDrive "destination.bin"
        $sourceBytes = [byte[]](0..255)
        [System.IO.File]::WriteAllBytes($sourcePath, $sourceBytes)
        $reportedProgress = [System.Collections.Generic.List[int]]::new()

        Save-WinUtilFile -Uri ([uri]::new($sourcePath, [System.UriKind]::Absolute)) -DestinationPath $destinationPath -ProgressCallback {
            param($percent)
            $reportedProgress.Add($percent)
        }

        [System.IO.File]::ReadAllBytes($destinationPath) | Should -Be $sourceBytes
        $reportedProgress[-1] | Should -Be 100
    }

    It "informa o tamanho total em bytes junto com a porcentagem" {
        $sourcePath = Join-Path $TestDrive "sized.bin"
        $destinationPath = Join-Path $TestDrive "sized-copy.bin"
        [System.IO.File]::WriteAllBytes($sourcePath, [byte[]](0..255))
        $reported = [System.Collections.Generic.List[hashtable]]::new()

        Save-WinUtilFile -Uri ([uri]::new($sourcePath, [System.UriKind]::Absolute)) -DestinationPath $destinationPath -ProgressCallback {
            param($percent, $totalBytes)
            $reported.Add(@{ Percent = $percent; Total = $totalBytes })
        }

        $reported[-1].Percent | Should -Be 100
        $reported[-1].Total | Should -Be 256
    }
}

Describe "Invoke-WPFOOSU" {
    BeforeEach {
        New-WinUtilOOSUTestContext
        $script:capturedJob = $null

        Mock Start-WinUtilJob {
            $script:capturedJob = [pscustomobject]@{
                Name = $Name
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
            }
        }
        Mock Step-WinUtilJob { }
        Mock Show-WinUtilMessage { }
        Mock Write-WinUtilLog { }
        Mock Start-Process { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "enfileira o download como um trabalho com o caminho de download" {
        Invoke-WPFOOSU

        Should -Invoke Start-WinUtilJob -Times 1 -Exactly -ParameterFilter { $Name -eq "OOSU" }
        $script:capturedJob.Parameters.DownloadPath | Should -Be (Join-Path $TestDrive "ooshutup10.exe")
    }

    It "mapeia o progresso do download para o indicador do trabalho e lança o O&O ShutUp10++" {
        Mock Save-WinUtilFile {
            & $ProgressCallback 35
            & $ProgressCallback 100
        }

        Invoke-WPFOOSU
        $jobParameters = $script:capturedJob.Parameters
        & $script:capturedJob.ScriptBlock @jobParameters

        Should -Invoke Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Downloading O&O ShutUp10++ (35%)" -and $Percent -eq 35
        }
        Should -Invoke Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Launching O&O ShutUp10++" -and $Percent -eq 100
        }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq (Join-Path $TestDrive "ooshutup10.exe")
        }
    }

    It "mostra o tamanho do download ao lado da porcentagem" {
        Mock Save-WinUtilFile {
            & $ProgressCallback 35 85689344
        }

        Invoke-WPFOOSU
        $jobParameters = $script:capturedJob.Parameters
        & $script:capturedJob.ScriptBlock @jobParameters

        Should -Invoke Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Downloading O&O ShutUp10++ (35% of 82 MB)" -and $Percent -eq 35
        }
    }

    It "usa apenas a porcentagem quando o servidor não envia o tamanho" {
        Mock Save-WinUtilFile {
            & $ProgressCallback 100 -1
        }

        Invoke-WPFOOSU
        $jobParameters = $script:capturedJob.Parameters
        & $script:capturedJob.ScriptBlock @jobParameters

        Should -Invoke Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Downloading O&O ShutUp10++ (100%)" -and $Percent -eq 100
        }
    }

    It "permite que uma falha de download apareça para que a camada de trabalhos possa tratá-la" {
        Mock Save-WinUtilFile { throw "download failed" }

        Invoke-WPFOOSU
        $jobParameters = $script:capturedJob.Parameters

        { & $script:capturedJob.ScriptBlock @jobParameters } | Should -Throw "download failed"
        Should -Not -Invoke Start-Process
    }
}

Describe "Botão O&O ShutUp10++" {
    It "informa ao usuário que baixa a ferramenta antes de qualquer coisa começar" {
        $tweaks = Get-Content (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json

        $tweaks.WPFOOSUbutton.Description | Should -Match "(?i)download"
        $tweaks.WPFOOSUbutton.Description | Should -Match "MB"
    }

    It "é renderizado com sua descrição como dica" {
        $renderer = Get-Content (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIElements.ps1") -Raw

        $renderer | Should -Match '\$button\.ToolTip\s*=\s*\$entryInfo\.Description'
    }
}
