# Executa os scripts configurados pelo orquestrador de ajustes real. Cada cmdlet de registro
# é mockado para que estes testes nunca toquem o banco de dados de exibição do Explorer da máquina.
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'functions/private/Invoke-WinUtilTweaks.ps1')
    $script:explorerTweaks = Get-Content (Join-Path $repoRoot 'config/tweaks.json') -Raw | ConvertFrom-Json
    $script:shellRoot = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell'
    $script:bagKeys = @("$script:shellRoot\Bags", "$script:shellRoot\BagMRU")
    function Write-WinUtilLog { param($Level, $Component, $Message) }
    function Invoke-WinUtilScript { param($Name, [scriptblock]$ScriptBlock) }
}

Describe 'Aplicação e desfazer da descoberta automática de pastas do Explorer' {
    BeforeEach {
        $script:sync = @{ configs = @{ tweaks = $script:explorerTweaks } }
        $script:existingKeys = @()
        Mock Test-Path { $script:existingKeys -contains $Path }
        Mock Remove-Item { }
        Mock New-Item { }
        Mock New-ItemProperty { }
        Mock Invoke-WinUtilScript { & $ScriptBlock }
        Mock Write-WinUtilLog { }
        Mock Write-Host { }
    }

    AfterEach {
        Remove-Variable sync -Scope Script -ErrorAction SilentlyContinue
    }

    It 'apaga ambas as chaves do banco de dados de exibição quando existem' {
        $script:existingKeys = $script:bagKeys
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableExplorerAutoDiscovery'
        foreach ($key in $script:bagKeys) {
            Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $Path -eq $key -and $Recurse -and $Force }
        }
    }

    It 'ignora a remoção quando o Explorer ainda não criou as chaves' {
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableExplorerAutoDiscovery'
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    # Aplicar o ajuste recria Bags\AllFolders, então uma segunda aplicação encontra Bags sem BagMRU.
    It 'remove Bags e ignora BagMRU quando apenas Bags existe' {
        $bags, $bagMRU = $script:bagKeys
        $script:existingKeys = @($bags)
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableExplorerAutoDiscovery'
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $Path -eq $bags -and $Recurse -and $Force }
        Should -Invoke Remove-Item -Times 0 -Exactly -ParameterFilter { $Path -eq $bagMRU }
    }

    It 'ainda cria AllFolders e define a exibição genérica quando as chaves estão ausentes' {
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableExplorerAutoDiscovery'
        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $Path -eq "$script:shellRoot\Bags\AllFolders\Shell" }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'FolderType' -and $Value -eq 'NotSpecified' }
    }

    It 'o desfazer apaga ambas as chaves quando existem e as ignora quando estão ausentes' {
        $script:existingKeys = $script:bagKeys
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableExplorerAutoDiscovery' -undo $true
        Should -Invoke Remove-Item -Times 2 -Exactly

        $script:existingKeys = @()
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableExplorerAutoDiscovery' -undo $true
        Should -Invoke Remove-Item -Times 2 -Exactly
    }
}
