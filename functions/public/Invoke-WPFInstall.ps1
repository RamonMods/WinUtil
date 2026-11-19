function Invoke-WPFInstall {
    <#
    .SYNOPSIS
        Instala os programas selecionados usando o winget. Se um ou mais dos programas selecionados já estiverem instalados no sistema, o winget tentará realizar uma atualização caso exista uma versão mais recente para instalar.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [PSObject[]]$PackagesToInstall = $($sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ })
    )

    if ($PackagesToInstall.Count -eq 0) {
        $WarningMsg = "Selecione o(s) programa(s) a instalar ou atualizar."
        Show-WinUtilMessage -Message $WarningMsg -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    $ManagerPreference = $sync.preferences.packagemanager
    Write-WinUtilLog -Component "Install" -Message "Instalação solicitada para $(@($PackagesToInstall).Count) pacote(s) selecionado(s) usando a preferência: $ManagerPreference"
    $packageSummary = Get-WinUtilPackageLogSummary -Packages $PackagesToInstall -Preference $ManagerPreference
    Write-WinUtilLog -Component "Install" -Message "Instalar pacote(s) selecionado(s): $($packageSummary -join '; ')"

    Start-WinUtilJob -Name "Install" -Description "Instalando aplicativos" -DisableAppList -QueueIfBusy -Parameters @{
        PackagesToInstall = $PackagesToInstall
        ManagerPreference = $ManagerPreference
    } -ScriptBlock {
        param($PackagesToInstall, $ManagerPreference)

        $packagesSorted = Get-WinUtilSelectedPackages -PackageList $PackagesToInstall -Preference $ManagerPreference
        $packagesWinget = $packagesSorted['Winget']
        $packagesChoco = $packagesSorted['Choco']
        $totalPackages = @($packagesWinget).Count + @($packagesChoco).Count
        $completedPackages = 0
        Write-WinUtilLog -Component "Install" -Message "Divisão dos pacotes por gerenciador: winget=$(@($packagesWinget).Count), choco=$(@($packagesChoco).Count)"

        $results = @()

        if ($packagesWinget.Count -gt 0 -and $packagesWinget -ne "0") {
            Install-WinUtilWinget
            foreach ($program in $packagesWinget) {
                $position = $completedPackages + 1
                Step-WinUtilJob -Status "Instalando $program ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

                $results += Measure-WinUtilStep -Scope "Install" -Name "winget $program" -ScriptBlock {
                    Install-WinUtilProgramWinget -Action Install -Programs @($program)
                }
                $completedPackages++
                Step-WinUtilJob -Status "$program instalado ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
            }
        }

        if ($packagesChoco.Count -gt 0) {
            $position = $completedPackages + 1
            Step-WinUtilJob -Status "Instalando pacotes do Chocolatey ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

            Install-WinUtilChoco
            $chocoBase = [int](($completedPackages / $totalPackages) * 100)
            $chocoSpan = [int]((@($packagesChoco).Count / $totalPackages) * 100)
            $results += Measure-WinUtilStep -Scope "Install" -Name "choco $($packagesChoco -join ', ')" -ScriptBlock {
                Install-WinUtilProgramChoco -Action Install -Programs $packagesChoco -ProgressBase $chocoBase -ProgressSpan $chocoSpan
            }
            $completedPackages += @($packagesChoco).Count
            Step-WinUtilJob -Status "Pacotes do Chocolatey instalados ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        Complete-WinUtilPackageRun -Action "Install" -Results $results
    }
}
