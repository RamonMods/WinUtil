BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $repoRoot "functions\public\Invoke-WPFImpex.ps1")
    . (Join-Path $repoRoot "functions\private\Update-WinUtilSelections.ps1")
}

Describe "Caminhos de arquivos de configuração" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                applicationsHashtable = @{ WPFInstallGit = @{}; WPFInstallFirefox = @{} }
            }
            selectedApps = [System.Collections.Generic.List[string]]::new()
            selectedTweaks = [System.Collections.Generic.List[string]]::new()
            selectedToggles = [System.Collections.Generic.List[string]]::new()
            selectedFeatures = [System.Collections.Generic.List[string]]::new()
            selectedAppx = [System.Collections.Generic.List[string]]::new()
        })
        Mock Set-Clipboard { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "importa o arquivo exato em <RelativePath> em vez de sua correspondência curinga" -ForEach @(
        @{ RelativePath = 'config[1].json'; DecoyPath = 'config1.json' }
        @{ RelativePath = '[backup]\config.json'; DecoyPath = 'b\config.json' }
    ) {
        $configPath = Join-Path $TestDrive $RelativePath
        $otherPath = Join-Path $TestDrive $DecoyPath
        [IO.Directory]::CreateDirectory((Split-Path $configPath)) | Out-Null
        [IO.Directory]::CreateDirectory((Split-Path $otherPath)) | Out-Null
        '"WPFInstallGit"' | Set-Content -LiteralPath $configPath
        '"WPFInstallFirefox"' | Set-Content -LiteralPath $otherPath

        Invoke-WPFImpex -type "import" -Config $configPath -ThrowOnError

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
    }

    It "importa JSON remoto sem análise de página web" {
        Mock Invoke-WebRequest {
            if (-not $UseBasicParsing) { throw "Unsafe web-page parsing requested" }
            [pscustomobject]@{ Content = '["WPFInstallGit"]' }
        }

        Invoke-WPFImpex -type "import" -Config "https://example.com/config.json" -ThrowOnError

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq "https://example.com/config.json" -and $UseBasicParsing
        }
    }

    It "rejeita uma resposta HTML remota sem alterar as seleções" {
        $script:sync.selectedApps.Add("WPFInstallFirefox")
        Mock Invoke-WebRequest {
            if (-not $UseBasicParsing) { throw "Unsafe web-page parsing requested" }
            [pscustomobject]@{ Content = '<html><body>Not a WinUtil config</body></html>' }
        }

        { Invoke-WPFImpex -type "import" -Config "https://example.com/config.json" -ThrowOnError } | Should -Throw

        @($script:sync.selectedApps) | Should -Be @("WPFInstallFirefox")
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $UseBasicParsing }
    }

    It "exporta para o arquivo exato em <RelativePath> sem sobrescrever sua correspondência curinga" -ForEach @(
        @{ RelativePath = 'export[1].json'; DecoyPath = 'export1.json' }
        @{ RelativePath = '[export]\config.json'; DecoyPath = 'e\config.json' }
    ) {
        $configPath = Join-Path $TestDrive $RelativePath
        $otherPath = Join-Path $TestDrive $DecoyPath
        [IO.Directory]::CreateDirectory((Split-Path $configPath)) | Out-Null
        [IO.Directory]::CreateDirectory((Split-Path $otherPath)) | Out-Null
        '"WPFInstallFirefox"' | Set-Content -LiteralPath $otherPath
        $script:sync.selectedApps.Add("WPFInstallGit")

        Invoke-WPFImpex -type "export" -Config $configPath

        Test-Path -LiteralPath $configPath | Should -BeTrue
        Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json | Should -Be "WPFInstallGit"
        Get-Content -LiteralPath $otherPath -Raw | ConvertFrom-Json | Should -Be "WPFInstallFirefox"
    }
}
