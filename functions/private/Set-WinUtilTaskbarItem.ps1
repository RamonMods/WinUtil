function Set-WinUtilTaskbaritem {
    <#

    .SYNOPSIS
        Modifica o item da barra de tarefas do formulário WPF

    .PARAMETER value
        O valor pode ser entre 0 e 1, sendo 0 nenhum progresso feito ainda e 1 totalmente concluído
        O valor não afeta o item sem definir o estado como 'Normal', 'Error' ou 'Paused'
        Set-WinUtilTaskbaritem -value 0.5

    .PARAMETER state
        O estado pode ser 'None' > Sem progresso, 'Indeterminate' > carregamento infinito cinza, 'Normal' > Cinza, 'Error' > Vermelho, 'Paused' > Amarelo
        não precisa de valor:
        - Set-WinUtilTaskbaritem -state "None"
        - Set-WinUtilTaskbaritem -state "Indeterminate"
        precisa de valor:
        - Set-WinUtilTaskbaritem -state "Error"
        - Set-WinUtilTaskbaritem -state "Normal"
        - Set-WinUtilTaskbaritem -state "Paused"

    .PARAMETER overlay
        Ícone de sobreposição a exibir no item da barra de tarefas; existem as predefinições 'None', 'logo' e 'checkmark' ou você pode especificar um caminho/link para um arquivo de imagem.
        Predefinição do logo do Ramon:
        - Set-WinUtilTaskbaritem -overlay "logo"
        Predefinição de marca de verificação:
        - Set-WinUtilTaskbaritem -overlay "checkmark"
        Predefinição de aviso:
        - Set-WinUtilTaskbaritem -overlay "warning"
        Sem sobreposição:
        - Set-WinUtilTaskbaritem -overlay "None"
        Ícone personalizado (precisa ser suportado pelo WPF):
        - Set-WinUtilTaskbaritem -overlay "C:\path\to\icon.png"

    .PARAMETER description
        Descrição a exibir na visualização do item da barra de tarefas
        Set-WinUtilTaskbaritem -description "Isto é uma descrição"
    #>
    param (
        [string]$state,
        [double]$value,
        [string]$overlay,
        [string]$description
    )

    if ($value) {
        $sync["Form"].taskbarItemInfo.ProgressValue = $value
    }

    if ($state) {
        switch ($state) {
            'None' { $sync["Form"].taskbarItemInfo.ProgressState = "None" }
            'Indeterminate' { $sync["Form"].taskbarItemInfo.ProgressState = "Indeterminate" }
            'Normal' { $sync["Form"].taskbarItemInfo.ProgressState = "Normal" }
            'Error' { $sync["Form"].taskbarItemInfo.ProgressState = "Error" }
            'Paused' { $sync["Form"].taskbarItemInfo.ProgressState = "Paused" }
            default { throw "[Set-WinUtilTaskbarItem] Estado inválido" }
        }
    }

    if ($overlay) {
        switch ($overlay) {
            'logo' {
                if (-not $sync["logorender"]) {
                    Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo $true -IncludeStatusAssets $false
                }
                $sync["Form"].taskbarItemInfo.Overlay = $sync["logorender"]
            }
            'checkmark' {
                if (-not $sync["checkmarkrender"]) {
                    Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo $false -IncludeStatusAssets $true
                }
                $sync["Form"].taskbarItemInfo.Overlay = $sync["checkmarkrender"]
            }
            'warning' {
                if (-not $sync["warningrender"]) {
                    Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo $false -IncludeStatusAssets $true
                }
                $sync["Form"].taskbarItemInfo.Overlay = $sync["warningrender"]
            }
            'None' {
                $sync["Form"].taskbarItemInfo.Overlay = $null
            }
            default {
                if (Test-Path $overlay) {
                    $sync["Form"].taskbarItemInfo.Overlay = $overlay
                }
            }
        }
    }

    if ($description) {
        $sync["Form"].taskbarItemInfo.Description = $description
    }
}
