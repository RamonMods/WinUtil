function Invoke-WPFUnInstall {
    param(
        [Parameter(Mandatory=$false)]
        [PSObject[]]$PackagesToUninstall = $($sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ })
    )
    <#

    .SYNOPSIS
        Desinstala os programas selecionados
    #>

    if ($PackagesToUninstall.Count -eq 0) {
        $WarningMsg = "Selecione o(s) programa(s) a desinstalar"
        Show-WinUtilMessage -Message $WarningMsg -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    $ButtonType = "YesNo"
    $MessageboxTitle = "Tem certeza?"
    $Messageboxbody = ("Isso desinstalará os seguintes aplicativos: `n $($PackagesToUninstall | Select-Object Name, Description| Out-String)")
    $MessageIcon = "Information"

    $confirm = Show-WinUtilMessage -Message $Messageboxbody -Title $MessageboxTitle -Button $ButtonType -Icon $MessageIcon

    if ($confirm -ne "Yes") { return }

    $ManagerPreference = $sync.preferences.packagemanager
    Write-WinUtilLog -Component "Uninstall" -Message "Desinstalação solicitada para $(@($PackagesToUninstall).Count) pacote(s) selecionado(s) usando a preferência: $ManagerPreference"
    $packageSummary = Get-WinUtilPackageLogSummary -Packages $PackagesToUninstall -Preference $ManagerPreference
    Write-WinUtilLog -Component "Uninstall" -Message "Desinstalar pacote(s) selecionado(s): $($packageSummary -join '; ')"

    Start-WinUtilJob -Name "Uninstall" -Description "Desinstalando aplicativos" -DisableAppList -QueueIfBusy -Parameters @{
        PackagesToUninstall = $PackagesToUninstall
        ManagerPreference = $ManagerPreference
    } -ScriptBlock {
        param($PackagesToUninstall, $ManagerPreference)

        $packagesSorted = Get-WinUtilSelectedPackages -PackageList $PackagesToUninstall -Preference $ManagerPreference -Action Uninstall
        $packagesWinget = $packagesSorted['Winget']
        $packagesChoco = $packagesSorted['Choco']
        $totalPackages = @($packagesWinget).Count + @($packagesChoco).Count
        $completedPackages = 0
        Write-WinUtilLog -Component "Uninstall" -Message "Divisão dos pacotes por gerenciador na desinstalação: winget=$(@($packagesWinget).Count), choco=$(@($packagesChoco).Count)"

        if ($packagesWinget -contains "Microsoft.Edge") {
            New-Item -Path "$Env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe" -Force | Out-Null
        }

        $results = @()

        if ($packagesWinget.Count -gt 0) {
            foreach ($program in $packagesWinget) {
                $position = $completedPackages + 1
                Step-WinUtilJob -Status "Desinstalando $program ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

                $results += Measure-WinUtilStep -Scope "Uninstall" -Name "winget $program" -ScriptBlock {
                    Install-WinUtilProgramWinget -Action Uninstall -Programs @($program)
                }
                $completedPackages++
                Step-WinUtilJob -Status "Desinstalado $program ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
            }
        }

        if ($packagesChoco.Count -gt 0) {
            $position = $completedPackages + 1
            Step-WinUtilJob -Status "Desinstalando pacotes do Chocolatey ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

            $chocoBase = [int](($completedPackages / $totalPackages) * 100)
            $chocoSpan = [int]((@($packagesChoco).Count / $totalPackages) * 100)
            $results += Measure-WinUtilStep -Scope "Uninstall" -Name "choco $($packagesChoco -join ', ')" -ScriptBlock {
                Install-WinUtilProgramChoco -Action Uninstall -Programs $packagesChoco -ProgressBase $chocoBase -ProgressSpan $chocoSpan
            }
            $completedPackages += @($packagesChoco).Count
            Step-WinUtilJob -Status "Pacotes do Chocolatey desinstalados ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        Complete-WinUtilPackageRun -Action "Uninstall" -Results $results
    }
}
