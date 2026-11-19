#===========================================================================
# Testes - Orquestração de ajustes
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Measure-WinUtilStep.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilTweaks.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFtweaksbutton.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFundoall.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilTweakDisplayName.ps1")

    function Set-WinUtilService {
        param($Name, $StartupType)
    }
    function Get-Service {
        [CmdletBinding()]
        param($Name)
    }
    function Set-WinUtilRegistry {
        param($Name, $Path, $Type, $Value)
    }
    function Invoke-WinUtilScript {
        param($Name, [scriptblock]$ScriptBlock)
    }
    function Remove-WinUtilAPPX {
        param($Name)
    }
    function Remove-WinUtilProvisionedAPPX {
        param($PackageList)
    }
    function Set-WinUtilDNS {
        param($DNSProvider)
    }
    function Invoke-WPFRunspace {
        param($ArgumentList, $ParameterList, [scriptblock]$ScriptBlock)
    }
    function Invoke-WPFUIThread {
        param([scriptblock]$ScriptBlock, [hashtable]$Parameters, [switch]$Async)
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Start-WinUtilJob {
        param([string]$Name, [scriptblock]$ScriptBlock, [hashtable]$Parameters, [string]$Description, [switch]$DisableAppList)
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }

    function script:New-WinUtilTweaksConfig {
        [pscustomobject]@{
            WPFTweaksExample = [pscustomobject]@{
                service = @(
                    [pscustomobject]@{
                        Name = "DiagTrack"
                        StartupType = "Disabled"
                        OriginalType = "Automatic"
                    }
                )
                registry = @(
                    [pscustomobject]@{
                        Path = "HKLM:\Software\WinUtilTest"
                        Name = "AllowTelemetry"
                        Type = "DWord"
                        Value = "0"
                        OriginalValue = "1"
                    }
                )
                InvokeScript = @("Write-Output 'apply tweak'")
                UndoScript = @("Write-Output 'undo tweak'")
                appx = @("Microsoft.ExampleApp")
            }
            WPFTweaksServiceOnly = [pscustomobject]@{
                service = @(
                    [pscustomobject]@{
                        Name = "DiagTrack"
                        StartupType = "Disabled"
                        OriginalType = "Automatic"
                    }
                )
            }
        }
    }
}

Describe "Invoke-WinUtilTweaks" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                tweaks = New-WinUtilTweaksConfig
            }
        })

        Mock Get-Service {
            [pscustomobject]@{
                Name = "DiagTrack"
                StartType = "Automatic"
            }
        }
        Mock Set-WinUtilService { }
        Mock Set-WinUtilRegistry { }
        Mock Invoke-WinUtilScript { }
        Mock Remove-WinUtilAPPX { }
        Mock Remove-WinUtilProvisionedAPPX { }
        Mock Write-WinUtilLog { }
        Mock Write-Warning { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "envia ações de aplicação para os auxiliares de serviço, registro, script e AppX" {
        Invoke-WinUtilTweaks -CheckBox "WPFTweaksExample"

        Should -Invoke -CommandName Get-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "DiagTrack" -and $ErrorAction -eq "Stop"
        }
        Should -Invoke -CommandName Set-WinUtilService -Times 1 -Exactly -ParameterFilter {
            $Name -eq "DiagTrack" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Set-WinUtilRegistry -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\Software\WinUtilTest" -and
                $Name -eq "AllowTelemetry" -and
                $Type -eq "DWord" -and
                $Value -eq "0"
        }
        Should -Invoke -CommandName Invoke-WinUtilScript -Times 1 -Exactly -ParameterFilter {
            $Name -eq "WPFTweaksExample" -and $ScriptBlock.ToString() -eq "Write-Output 'apply tweak'"
        }
        Should -Invoke -CommandName Remove-WinUtilAPPX -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Microsoft.ExampleApp"
        }
        Should -Invoke -CommandName Remove-WinUtilProvisionedAPPX -Times 1 -Exactly -ParameterFilter {
            $PackageList.Count -eq 1 -and $PackageList[0] -eq "Microsoft.ExampleApp"
        }
    }

    It "usa os valores originais do registro e os tipos de inicialização de serviço no modo de desfazer" {
        Mock Get-Service {
            [pscustomobject]@{
                Name = "DiagTrack"
                StartType = "Disabled"
            }
        } -ParameterFilter { $Name -eq "DiagTrack" }

        Invoke-WinUtilTweaks -CheckBox "WPFTweaksExample" -undo $true

        Should -Invoke -CommandName Get-Service -Times 1 -Exactly
        Should -Invoke -CommandName Set-WinUtilService -Times 1 -Exactly -ParameterFilter {
            $Name -eq "DiagTrack" -and $StartupType -eq "Automatic"
        }
        Should -Invoke -CommandName Set-WinUtilRegistry -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\Software\WinUtilTest" -and
                $Name -eq "AllowTelemetry" -and
                $Type -eq "DWord" -and
                $Value -eq "1"
        }
        Should -Invoke -CommandName Invoke-WinUtilScript -Times 1 -Exactly -ParameterFilter {
            $Name -eq "WPFTweaksExample" -and $ScriptBlock.ToString() -eq "Write-Output 'undo tweak'"
        }
        Should -Invoke -CommandName Remove-WinUtilAPPX -Times 0 -Exactly
        Should -Invoke -CommandName Remove-WinUtilProvisionedAPPX -Times 0 -Exactly
    }

    It "mantém por padrão o tipo de inicialização de serviço alterado pelo usuário" {
        Mock Get-Service {
            [pscustomobject]@{
                Name = "DiagTrack"
                StartType = "Manual"
            }
        } -ParameterFilter { $Name -eq "DiagTrack" }

        Invoke-WinUtilTweaks -CheckBox "WPFTweaksServiceOnly"

        Should -Invoke -CommandName Get-Service -Times 1 -Exactly
        Should -Invoke -CommandName Set-WinUtilService -Times 0 -Exactly
        # A omissão é relatada, para que o log não pareça que o ajuste alterou o serviço
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -match "DiagTrack.*Manual.*Automatic"
        }
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -match "DiagTrack.*Manual.*Automatic"
        }
    }

    It "não altera um serviço ao desfazer quando seu tipo de inicialização não é o valor aplicado" {
        Mock Get-Service {
            [pscustomobject]@{
                Name = "DiagTrack"
                StartType = "Manual"
            }
        } -ParameterFilter { $Name -eq "DiagTrack" }

        Invoke-WinUtilTweaks -CheckBox "WPFTweaksServiceOnly" -undo $true

        Should -Invoke -CommandName Get-Service -Times 1 -Exactly
        Should -Invoke -CommandName Set-WinUtilService -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -match "DiagTrack.*Manual.*Disabled"
        }
    }

    It "força o serviço de volta ao seu tipo de inicialização original ao desfazer quando ele ainda corresponde ao valor aplicado" {
        Mock Get-Service {
            [pscustomobject]@{
                Name = "DiagTrack"
                StartType = "Disabled"
            }
        } -ParameterFilter { $Name -eq "DiagTrack" }

        Invoke-WinUtilTweaks -CheckBox "WPFTweaksServiceOnly" -undo $true

        Should -Invoke -CommandName Set-WinUtilService -Times 1 -Exactly -ParameterFilter {
            $Name -eq "DiagTrack" -and $StartupType -eq "Automatic"
        }
    }

    It "descarta o status de interruptor em cache para que a próxima leitura consulte o registro" {
        $script:sync.ToggleStatusCache = @{ WPFTweaksServiceOnly = $true }

        Invoke-WinUtilTweaks -CheckBox "WPFTweaksServiceOnly"

        $script:sync.ToggleStatusCache.ContainsKey("WPFTweaksServiceOnly") | Should -BeFalse
    }

    It "força um tipo de inicialização de serviço quando KeepServiceStartup está desativado" {
        Invoke-WinUtilTweaks -CheckBox "WPFTweaksServiceOnly" -KeepServiceStartup $false

        Should -Invoke -CommandName Get-Service -Times 0 -Exactly
        Should -Invoke -CommandName Set-WinUtilService -Times 1 -Exactly -ParameterFilter {
            $Name -eq "DiagTrack" -and $StartupType -eq "Disabled"
        }
    }

    It "ignora um serviço ausente e aplica os demais serviços e ajustes" {
        $script:sync.configs.tweaks.WPFTweaksExample.service = @(
            [pscustomobject]@{
                Name = "CscService"
                StartupType = "Disabled"
                OriginalType = "Manual"
            }
        ) + $script:sync.configs.tweaks.WPFTweaksExample.service

        Mock Get-Service {
            $exception = [System.Exception]::new("Cannot find any service with service name '$Name'.")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                "NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.GetServiceCommand",
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Name
            )
            throw $errorRecord
        } -ParameterFilter { $Name -eq "CscService" -and $ErrorAction -eq "Stop" }

        foreach ($tweak in @("WPFTweaksExample", "WPFTweaksServiceOnly")) {
            Invoke-WinUtilTweaks -CheckBox $tweak
        }

        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Service CscService was not found."
        }
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Component -eq "Service" -and $Message -eq "Service CscService was not found."
        }
        Should -Invoke -CommandName Set-WinUtilService -Times 0 -Exactly -ParameterFilter {
            $Name -eq "CscService"
        }
        Should -Invoke -CommandName Set-WinUtilService -Times 2 -Exactly -ParameterFilter {
            $Name -eq "DiagTrack" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Invoke-WinUtilScript -Times 1 -Exactly -ParameterFilter {
            $Name -eq "WPFTweaksExample"
        }
    }

    It "relança erros de busca de serviço que não identificam um serviço ausente" {
        Mock Get-Service {
            $exception = [System.Exception]::new("Service lookup failed.")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                "ServiceLookupFailed",
                [System.Management.Automation.ErrorCategory]::OpenError,
                $Name
            )
            throw $errorRecord
        }

        { Invoke-WinUtilTweaks -CheckBox "WPFTweaksExample" } | Should -Throw -ExpectedMessage "*Service lookup failed.*"

        Should -Invoke -CommandName Set-WinUtilService -Times 0 -Exactly
        Should -Invoke -CommandName Set-WinUtilRegistry -Times 0 -Exactly
        Should -Invoke -CommandName Invoke-WinUtilScript -Times 0 -Exactly
        Should -Invoke -CommandName Write-Warning -Times 0 -Exactly
    }
}

Describe "Status de conclusão de Invoke-WinUtilTweaks" {
    BeforeAll {
        . (Join-Path $script:repoRoot "functions\private\Write-WinUtilLog.ps1")
        . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilScript.ps1")
    }

    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "winutil-tweaks-$([guid]::NewGuid())"
        $script:logPath = Join-Path $script:testRoot "logs\winutil_2026-09-15_12-00-00.log"
        $script:sync = [Hashtable]::Synchronized(@{
            logPath = $script:logPath
            configs = @{
                tweaks = [pscustomobject]@{
                    WPFTweaksFailing = [pscustomobject]@{
                        InvokeScript = @("throw 'simulated icacls failure'")
                        UndoScript = @("throw 'simulated icacls undo failure'")
                    }
                    WPFTweaksClean = [pscustomobject]@{
                        InvokeScript = @("Write-Output 'apply tweak'")
                    }
                    # Um worker do job que registra um erro em seu próprio runspace vai parar na lista
                    # compartilhada sem passar pelo agente de log deste runspace
                    WPFTweaksDuringJob = [pscustomobject]@{
                        InvokeScript = @("`$null = `$sync.LoggedErrors.Add('[Job] error from a concurrent job'); Write-Output 'apply tweak'")
                    }
                }
            }
            # Inicializado com um erro anterior: apenas erros registrados durante este ajuste podem contar
            LoggedErrors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new(@("[UI] earlier unrelated failure")))
        })
        # Interruptores executam o ajuste na thread da interface, fora de qualquer worker de job. O contador do
        # runspace começa diferente de zero: apenas erros registrados durante este ajuste podem contar
        Remove-Variable -Name WinUtilIsJobWorker -Scope Global -ErrorAction SilentlyContinue
        $global:WinUtilJobErrorCount = 3

        Mock Write-Host { }
        Mock Write-Warning { }
    }

    AfterEach {
        Close-WinUtilLog
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name WinUtilJobErrorCount -Scope Global -ErrorAction SilentlyContinue
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "avisa em vez de relatar conclusão quando uma etapa de ajuste registrou um erro" {
        Invoke-WinUtilTweaks -CheckBox "WPFTweaksFailing"

        $log = Get-Content -Path $script:logPath -Raw
        $log | Should -Match "\[ERROR\] \[Script\] Runtime exception while running script for WPFTweaksFailing"
        $log | Should -Match "\[WARN\] \[Tweaks\] Apply tweak finished with 1 error\(s\): WPFTweaksFailing"
        $log | Should -Not -Match "tweak completed: WPFTweaksFailing"
    }

    It "avisa quando uma etapa de desfazer registrou um erro" {
        Invoke-WinUtilTweaks -CheckBox "WPFTweaksFailing" -undo $true

        $log = Get-Content -Path $script:logPath -Raw
        $log | Should -Match "\[ERROR\] \[Script\] Runtime exception while running script for WPFTweaksFailing"
        $log | Should -Match "\[WARN\] \[Tweaks\] Undo tweak finished with 1 error\(s\): WPFTweaksFailing"
        $log | Should -Not -Match "tweak completed: WPFTweaksFailing"
    }

    It "relata conclusão quando todas as etapas de ajuste tiveram sucesso" {
        Invoke-WinUtilTweaks -CheckBox "WPFTweaksClean"

        $log = Get-Content -Path $script:logPath -Raw
        $log | Should -Match "\[INFO\] \[Tweaks\] Apply tweak completed: WPFTweaksClean"
        $log | Should -Not -Match "\[WARN\]"
        $log | Should -Not -Match "\[ERROR\]"
    }

    It "ignora um erro registrado por outro runspace enquanto o ajuste era executado" {
        Invoke-WinUtilTweaks -CheckBox "WPFTweaksDuringJob"

        $log = Get-Content -Path $script:logPath -Raw
        $log | Should -Match "\[INFO\] \[Tweaks\] Apply tweak completed: WPFTweaksDuringJob"
        $log | Should -Not -Match "tweak finished with"
    }
}

Describe "Get-WinUtilTweakDisplayName" {
    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "retorna o rótulo Content configurado" {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                tweaks = [pscustomobject]@{
                    WPFTweaksTelemetry = [pscustomobject]@{ Content = "Telemetry - Disable" }
                }
            }
        })

        Get-WinUtilTweakDisplayName -Key "WPFTweaksTelemetry" | Should -Be "Telemetry - Disable"
    }

    It "usa a chave como fallback quando a entrada ou as configurações estão ausentes" {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{ tweaks = [pscustomobject]@{} }
        })

        Get-WinUtilTweakDisplayName -Key "WPFTweaksUnknown" | Should -Be "WPFTweaksUnknown"

        $script:sync = [Hashtable]::Synchronized(@{})

        Get-WinUtilTweakDisplayName -Key "WPFTweaksUnknown" | Should -Be "WPFTweaksUnknown"
    }
}

Describe "Invoke-WPFtweaksbutton" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            selectedTweaks = [System.Collections.Generic.List[string]]::new()
            WPFchangedns = [pscustomobject]@{
                text = "Cloudflare"
            }
            configs = @{
                tweaks = [pscustomobject]@{
                    WPFTweaksTelemetry = [pscustomobject]@{ Content = "Telemetry - Disable" }
                    WPFTweaksServices = [pscustomobject]@{ Content = "Services - Set to Manual" }
                }
            }
        })
        $script:capturedTweaksJob = $null

        Mock Invoke-WinUtilTweaks { }
        # o real retorna $true em caso de sucesso, e o fluxo agora para quando não retorna
        Mock Set-WinUtilDNS { return $true }
        Mock Invoke-WPFUIThread { }
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
        Mock Show-WinUtilMessage { "OK" }
        Mock Write-Host { }
        Mock Start-WinUtilJob {
            $script:capturedTweaksJob = [pscustomobject]@{
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
            }
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedTweaksJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "solicita confirmação e sai quando nada está selecionado e o DNS permanece no padrão" {
        $script:sync.WPFchangedns.text = "Default"

        Invoke-WPFtweaksbutton

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Please check the tweaks you wish to perform."
        }
        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }

    It "enfileira um job de ajustes com a seleção e o provedor de DNS" {
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        $script:sync.selectedTweaks.Add("WPFTweaksServices")

        Invoke-WPFtweaksbutton

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Tweaks" -and $ScriptBlock -is [scriptblock]
        }
        $script:capturedTweaksJob.Parameters.Tweaks | Should -HaveCount 2
        $script:capturedTweaksJob.Parameters.Tweaks[0] | Should -Be "WPFTweaksTelemetry"
        $script:capturedTweaksJob.Parameters.DnsProvider | Should -Be "Cloudflare"
    }

    It "aplica cada ajuste selecionado e o provedor de DNS dentro do corpo do job" {
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        $script:sync.selectedTweaks.Add("WPFTweaksServices")

        Invoke-WPFtweaksbutton
        $jobParameters = $script:capturedTweaksJob.Parameters
        & $script:capturedTweaksJob.ScriptBlock @jobParameters

        Should -Invoke -CommandName Set-WinUtilDNS -Times 1 -Exactly -ParameterFilter {
            $DNSProvider -eq "Cloudflare"
        }
        Should -Invoke -CommandName Invoke-WinUtilTweaks -Times 2 -Exactly
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Applying Telemetry - Disable (1/2)" -and $Percent -eq 0
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Applying Services - Set to Manual (2/2)" -and $Percent -eq 50
        }
    }

    It "interrompe a execução quando a alteração de DNS falha" {
        # continuar deixaria a máquina meio configurada, então o job termina e relata isso
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        Mock Set-WinUtilDNS { return $false }

        Invoke-WPFtweaksbutton
        $jobParameters = $script:capturedTweaksJob.Parameters

        { & $script:capturedTweaksJob.ScriptBlock @jobParameters } | Should -Throw -ExpectedMessage "*DNS change to Cloudflare failed*"
        Should -Invoke -CommandName Invoke-WinUtilTweaks -Times 0 -Exactly
    }

    It "continua quando a alteração de DNS tem sucesso" {
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        Mock Set-WinUtilDNS { return $true }

        Invoke-WPFtweaksbutton
        $jobParameters = $script:capturedTweaksJob.Parameters
        & $script:capturedTweaksJob.ScriptBlock @jobParameters

        Should -Invoke -CommandName Invoke-WinUtilTweaks -Times 1 -Exactly
    }

    It "cria o ponto de restauração antes de qualquer outro ajuste ser executado" {
        $script:sync.selectedTweaks.Add("WPFTweaksRestorePoint")
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        $script:appliedOrder = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-WinUtilTweaks { $script:appliedOrder.Add($CheckBox) }

        Invoke-WPFtweaksbutton
        $jobParameters = $script:capturedTweaksJob.Parameters
        & $script:capturedTweaksJob.ScriptBlock @jobParameters

        $script:appliedOrder | Should -Be @("WPFTweaksRestorePoint", "WPFTweaksTelemetry")
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Creating restore point" -and $Percent -eq 0
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Applying Telemetry - Disable (2/2)" -and $Percent -eq 50
        }
    }

    It "usa a chave do ajuste como fallback quando nenhum rótulo está configurado" {
        $script:sync.configs.tweaks = [pscustomobject]@{}
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")

        Invoke-WPFtweaksbutton
        $jobParameters = $script:capturedTweaksJob.Parameters
        & $script:capturedTweaksJob.ScriptBlock @jobParameters

        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Applying WPFTweaksTelemetry (1/1)" -and $Percent -eq 0
        }
    }
}

Describe "Invoke-WPFundoall" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            selectedTweaks = [System.Collections.Generic.List[string]]::new()
            configs = @{
                tweaks = [pscustomobject]@{
                    WPFTweaksTelemetry = [pscustomobject]@{ Content = "Telemetry - Disable" }
                    WPFTweaksServices = [pscustomobject]@{ Content = "Services - Set to Manual" }
                }
            }
        })
        $script:capturedUndoJob = $null

        Mock Invoke-WinUtilTweaks { }
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
        Mock Show-WinUtilMessage { "OK" }
        Mock Write-Host { }
        Mock Start-WinUtilJob {
            $script:capturedUndoJob = [pscustomobject]@{
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
            }
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedUndoJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "solicita confirmação e sai quando nada está selecionado" {
        Invoke-WPFundoall

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Please check the tweaks you wish to undo."
        }
        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }

    It "desfaz cada ajuste selecionado dentro do corpo do job" {
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        $script:sync.selectedTweaks.Add("WPFTweaksServices")

        Invoke-WPFundoall

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Undo tweaks"
        }
        $jobParameters = $script:capturedUndoJob.Parameters
        & $script:capturedUndoJob.ScriptBlock @jobParameters

        Should -Invoke -CommandName Invoke-WinUtilTweaks -Times 2 -Exactly -ParameterFilter { $undo -eq $true }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Undoing Telemetry - Disable (1/2)" -and $Percent -eq 0
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Undoing Services - Set to Manual (2/2)" -and $Percent -eq 50
        }
    }
}
