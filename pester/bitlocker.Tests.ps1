#===========================================================================
# Testes - InvokeScript do ajuste de desabilitação do BitLocker
#===========================================================================
# Cobre WPFTweaksDisableBitLocker (config/tweaks.json): o script de aplicação deve
# consultar Get-BitLockerVolume e ignorar Disable-BitLocker quando VolumeStatus for
# FullyDecrypted. ProtectionStatus Off sozinho não basta: um volume criptografado
# com proteção suspensa ainda deve ser desabilitado. Falhas de consulta e de
# desabilitação devem se propagar, em vez de serem engolidas.

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:tweakName = "WPFTweaksDisableBitLocker"
    $tweaks = Get-Content -Path (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
    $script:invokeText = @($tweaks.$script:tweakName.InvokeScript) -join "`n"
    $script:invokeBlock = [scriptblock]::Create($script:invokeText)
    $script:undoText = @($tweaks.$script:tweakName.UndoScript) -join "`n"

    function Get-BitLockerVolume {
        [CmdletBinding()]
        param($MountPoint)
        throw "Get-BitLockerVolume must be mocked for $MountPoint."
    }
    function Disable-BitLocker {
        [CmdletBinding()]
        param($MountPoint)
        throw "Disable-BitLocker must be mocked for $MountPoint."
    }
}

Describe "WPFTweaksDisableBitLocker InvokeScript" {
    BeforeEach {
        Mock Get-BitLockerVolume { }
        Mock Disable-BitLocker { }
        Mock Write-Host { }
    }

    It "ignora Disable-BitLocker e reporta já desabilitado quando FullyDecrypted" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyDecrypted"
                ProtectionStatus     = "Off"
                EncryptionPercentage = 0
            }
        }

        & $script:invokeBlock

        Should -Invoke -CommandName Get-BitLockerVolume -Times 1 -Exactly -ParameterFilter {
            $MountPoint -eq $Env:SystemDrive
        }
        Should -Invoke -CommandName Disable-BitLocker -Times 0 -Exactly
        Should -Invoke -CommandName Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match "already disabled"
        }
    }

    It "ainda desabilita um volume criptografado com ProtectionStatus Off" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyEncrypted"
                ProtectionStatus     = "Off"
                EncryptionPercentage = 100
            }
        }

        & $script:invokeBlock

        Should -Invoke -CommandName Disable-BitLocker -Times 1 -Exactly -ParameterFilter {
            $MountPoint -eq $Env:SystemDrive
        }
    }

    It "desabilita um volume criptografado com ProtectionStatus On" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyEncrypted"
                ProtectionStatus     = "On"
                EncryptionPercentage = 100
            }
        }

        & $script:invokeBlock

        Should -Invoke -CommandName Disable-BitLocker -Times 1 -Exactly -ParameterFilter {
            $MountPoint -eq $Env:SystemDrive
        }
    }

    It "propaga falhas de Get-BitLockerVolume sem chamar Disable-BitLocker" {
        Mock Get-BitLockerVolume { throw "simulated BitLocker query failure" }

        { & $script:invokeBlock } | Should -Throw -ExpectedMessage "*simulated BitLocker query failure*"
        Should -Invoke -CommandName Get-BitLockerVolume -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
        Should -Invoke -CommandName Disable-BitLocker -Times 0 -Exactly
    }

    It "propaga falhas de Disable-BitLocker" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyEncrypted"
                ProtectionStatus     = "On"
                EncryptionPercentage = 100
            }
        }
        Mock Disable-BitLocker { throw "simulated BitLocker disable failure" }

        { & $script:invokeBlock } | Should -Throw -ExpectedMessage "*simulated BitLocker disable failure*"
    }

    It "faz com que um erro não terminante de desabilitação interrompa o script" {
        Mock Get-BitLockerVolume { [pscustomobject]@{ VolumeStatus = 'FullyEncrypted' } }
        Mock Disable-BitLocker { Write-Error 'simulated non-terminating disable failure' }
        { & $script:invokeBlock } | Should -Throw '*simulated non-terminating disable failure*'
        Should -Invoke Disable-BitLocker -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }
    It "preserva o script de desfazer Enable-BitLocker" {
        $script:undoText | Should -Match 'Enable-BitLocker -MountPoint \$Env:SystemDrive'
    }
}
