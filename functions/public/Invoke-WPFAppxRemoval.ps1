function Invoke-WPFAppxRemoval {
    <#

    .SYNOPSIS
        Remove os pacotes AppX selecionados

    #>

    if ($null -eq $sync.selectedAppx -or $sync.selectedAppx.Count -eq 0) {
        Show-WinUtilMessage -Message "Nenhum pacote AppX selecionado" -Title "Erro" -Button "OK" -Icon "Error"
        return
    }

    Start-WinUtilJob -Name "AppX" -Description "Removendo pacotes AppX" -QueueIfBusy -Parameters @{
        Selected = @($sync.selectedAppx)
        Apps = $sync.configs.appxHashtable
    } -ScriptBlock {
        param($Selected, $Apps)

        $total = @($Selected).Count
        $packageList = [System.Collections.Generic.List[string]]::new()
        Write-WinUtilLog -Component "AppX" -Message "Iniciando a remoção do AppX para $total pacote(s) selecionado(s)."

        for ($index = 0; $index -lt $total; $index++) {
            $key = $Selected[$index]
            $app = $Apps[$key]
            $position = $index + 1
            Step-WinUtilJob -Status "Removendo $($app.Content) ($position/$total)" -Percent ([int](($index / $total) * 90))

            if ($key -eq "WPFAppxMicrosoft_XboxGamingOverlay") {
                # Garantindo que o Game Bar não esteja em execução
                Write-WinUtilLog -Component "AppX" -Message "Interrompendo o GameBarFTServer antes de remover o Xbox Gaming Overlay."
                Stop-Process -Name GameBarFTServer -Force -Confirm:$false -ErrorAction SilentlyContinue

                # Isso impede o incômodo popup do ms-gamebar ao iniciar jogos.
                Write-WinUtilLog -Component "AppX" -Message "Desativando a captura do Game DVR antes de remover o Xbox Gaming Overlay."
                Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR -Name AppCaptureEnabled -Value 0
            }

            if ($key -eq "WPFAppxMicrosoft_WindowsNotepad") {
                Write-WinUtilLog -Component "AppX" -Message "Interrompendo o dllhost antes de remover o Notepad."
                Stop-Process -Name dllhost -Force -Confirm:$false -ErrorAction SilentlyContinue
            }

            Write-Host "Removendo $($app.Content)"
            Write-WinUtilLog -Component "AppX" -Message "Removendo $($app.Content) ($($app.PackageId))."
            Remove-WinUtilAPPX -Name $app.PackageId
            $packageList.Add($app.PackageId)

            if ($key -eq "WPFAppxMSTeams") {
                # Desinstala o suplemento de Reuniões do Microsoft Teams para o Microsoft Office
                Write-WinUtilLog -Component "AppX" -Message "Desinstalando o pacote do suplemento de reuniões do Microsoft Teams."
                Get-Package -Name "Microsoft Teams*" -ErrorAction SilentlyContinue | Uninstall-Package -Force
            }

            Step-WinUtilJob -Status "Removido $($app.Content) ($position/$total)" -Percent ([int](($position / $total) * 90))
        }

        if ($packageList.Count -gt 0) {
            Step-WinUtilJob -Status "Removendo pacotes AppX provisionados" -Percent 90
            Remove-WinUtilProvisionedAPPX -PackageList $packageList.ToArray()
        }
    }
}
