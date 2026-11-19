BeforeAll {
    $tweaks = Get-Content (Join-Path $PSScriptRoot '..\config\tweaks.json') -Raw | ConvertFrom-Json
    $script:removeEdge = [scriptblock]::Create($tweaks.WPFTweaksRemoveEdge.InvokeScript -join "`n")
    $script:edgeDirectory = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application"
    $script:installerPattern = Join-Path $script:edgeDirectory '*\Installer\setup.exe'
    $script:installerPath = Join-Path $script:edgeDirectory '123\Installer\setup.exe'
}

Describe 'Remoção do Edge' {
    BeforeEach {
        Mock Test-Path { $true }
        Mock Resolve-Path { $script:installerPath }
        Mock New-Item { }
        Mock Start-Process { }
        Mock Write-Host { }
    }

    It 'ignora um diretório de aplicativo ausente sem resolver um instalador' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq $script:edgeDirectory }

        & $script:removeEdge

        Should -Invoke Resolve-Path -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Microsoft Edge is not installed' }
    }

    It 'ignora um diretório sem instalador correspondente' {
        Mock Test-Path { $false } -ParameterFilter { $Path -eq $script:installerPattern }

        & $script:removeEdge

        Should -Invoke Resolve-Path -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Microsoft Edge is not installed' }
    }

    It 'usa o último instalador resolvido com os argumentos de desinstalação existentes' {
        Mock Resolve-Path {
            'C:\earlier\setup.exe'
            $script:installerPath
        }

        & $script:removeEdge

        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "$Env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe" -and $Force
        }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq $script:installerPath -and $Wait -and
            $ArgumentList -eq '--uninstall --system-level --force-uninstall --delete-profile'
        }
    }

    It 'mantém visíveis os erros de localização do diretório' {
        Mock Test-Path { throw 'Access denied' }

        { & $script:removeEdge } | Should -Throw '*Access denied*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'mantém visíveis as falhas de resolução do instalador' {
        Mock Resolve-Path { throw 'Installer resolution failed' }

        { & $script:removeEdge } | Should -Throw '*Installer resolution failed*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'não reporta remoção bem-sucedida quando a inicialização do desinstalador falha' {
        Mock Start-Process { throw 'Uninstaller launch failed' }

        { & $script:removeEdge } | Should -Throw '*Uninstaller launch failed*'
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { $Object -eq 'Microsoft Edge was removed' }
    }
}
