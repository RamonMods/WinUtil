function Invoke-WPFGetInstalled {
    <#
    .SYNOPSIS
        Detecta o que já está instalado ou aplicado e marca as caixas correspondentes

    .PARAMETER checkbox
        Indica se deve verificar programas 'winget' instalados ou 'tweaks' aplicados

    #>
    param($checkbox)

    if (($sync.ChocoRadioButton.IsChecked -eq $false) -and ((Test-WinUtilPackageManager -winget) -eq "not-installed") -and $checkbox -eq "winget") {
        return
    }

    Start-WinUtilJob -Name "Detect installed" -Description "Verificando o que já está instalado" -Parameters @{
        Checkbox = $checkbox
        ManagerPreference = $sync.preferences.packagemanager
    } -ScriptBlock {
        param($Checkbox, $ManagerPreference)

        Step-WinUtilJob -Status "Verificando o que já está instalado" -State "Indeterminate"

        $found = @()
        if ($Checkbox -eq "winget") {
            $source = if ($ManagerPreference -eq "Choco") { "choco" } else { $Checkbox }
            $found = @(Invoke-WinUtilCurrentSystem -CheckBox $source)
        } elseif ($Checkbox -eq "tweaks") {
            $found = @(Invoke-WinUtilCurrentSystem -CheckBox $Checkbox)
        }

        Write-WinUtilLog -Component "Install" -Message "Detectados $($found.Count) item(ns) existente(s) para $Checkbox."

        # Marcar caixas toca os controles, então isso acontece na thread de interface
        Invoke-WPFUIThread -Parameters @{ Checkbox = $Checkbox; Found = $found } -ScriptBlock {
            param($Checkbox, $Found)

            if ($Checkbox -eq "winget") {
                foreach ($name in $Found) {
                    if (-not $sync.selectedApps.Contains($name)) {
                        $sync.selectedApps.Add($name)
                    }
                }
                Reset-WPFCheckBoxes -checkboxfilterpattern "WPFInstall*"
            } else {
                foreach ($name in $Found) {
                    $sync.$name.ischecked = $true
                }
            }
        }
    }
}
