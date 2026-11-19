#===========================================================================
# Testes - Auxiliares de interface durante execuções headless (-Preset / -Config)
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    if (-not ("Windows.Visibility" -as [type])) {
        Add-Type @"
namespace Windows
{
    public enum Visibility
    {
        Visible,
        Collapsed
    }
}
"@
    }

    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIThread.ps1")

    function script:New-WinUtilFakeForm {
        $dispatcher = New-Object psobject
        $dispatcher | Add-Member -MemberType NoteProperty -Name InvokeCount -Value 0
        $dispatcher | Add-Member -MemberType NoteProperty -Name HasShutdownStarted -Value $false
        $dispatcher | Add-Member -MemberType ScriptMethod -Name CheckAccess -Value { return $false }
        $dispatcher | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
            param($Action)

            $null = $Action
            $this.InvokeCount++
        }

        $form = New-Object psobject
        $form | Add-Member -MemberType NoteProperty -Name Dispatcher -Value $dispatcher
        return $form
    }

    function script:New-WinUtilFakeIndicatorControlSet {
        @{
            Bar   = [pscustomobject]@{ Visibility = [Windows.Visibility]::Collapsed }
            Label = [pscustomobject]@{ Text = "" }
            Value = [pscustomobject]@{ Value = 0 }
        }
    }
}

Describe "Invoke-WPFUIThread sem janela" {
    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "não faz nada quando os caminhos de automação executam antes do formulário ser criado" {
        $script:sync = [Hashtable]::Synchronized(@{})
        $script:blockRan = $false

        { Invoke-WPFUIThread -ScriptBlock { $script:blockRan = $true } } | Should -Not -Throw
        $script:blockRan | Should -BeFalse
    }

    It "não faz nada quando o formulário existe mas não tem dispatcher" {
        $script:sync = [Hashtable]::Synchronized(@{ Form = [pscustomobject]@{ Dispatcher = $null } })
        $script:blockRan = $false

        { Invoke-WPFUIThread -ScriptBlock { $script:blockRan = $true } } | Should -Not -Throw
        $script:blockRan | Should -BeFalse
    }

    It "ainda encaminha para o dispatcher quando existe uma janela" {
        $form = New-WinUtilFakeForm
        $script:sync = [Hashtable]::Synchronized(@{ Form = $form })

        Invoke-WPFUIThread -ScriptBlock { }

        $form.Dispatcher.InvokeCount | Should -Be 1
    }
}
