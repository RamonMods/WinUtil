function Set-WinUtilClassicContextMenu {
    param([switch]$Undo)

    $clsidPath = 'HKCU:\Software\Classes\CLSID'
    $legacyPath = "$clsidPath\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $workaroundPath = "$clsidPath\{51668040-5e31-4023-bbe3-149163bd80f1}"
    $serverPath = "$workaroundPath\InprocServer32"
    $markerName = 'WinUtilClassicContextMenu'

    $workaroundKey = $null
    try {
        $workaroundKey = Get-Item -LiteralPath $workaroundPath -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        # A chave de registro mais recente é opcional.
    }
    $marker = if ($null -ne $workaroundKey) { $workaroundKey.GetValue($markerName) }
    $ownsWorkaround = $marker -is [int] -and $marker -eq 1

    if ($Undo) {
        # Versões antigas do WinUtil aplicavam a substituição original sem um marcador de propriedade.
        try {
            Remove-Item -LiteralPath $legacyPath -Recurse -Force -ErrorAction Stop
        } catch [System.Management.Automation.ItemNotFoundException] {
            # A substituição original já está ausente.
        }

        if ($ownsWorkaround) {
            try {
                if ($workaroundKey.ValueCount -gt 1 -or
                    ($workaroundKey.GetSubKeyNames() | Where-Object { $_ -ne 'InprocServer32' })) {
                    throw "A chave de registro do menu de contexto clássico '$workaroundPath' possui entradas adicionais e foi mantida intacta."
                }
                if ($workaroundKey.SubKeyCount -gt 0) {
                    $serverKey = Get-Item -LiteralPath $serverPath -ErrorAction Stop
                    if ($serverKey.SubKeyCount -gt 0 -or $serverKey.ValueCount -gt 1 -or
                        ($serverKey.ValueCount -eq 1 -and
                            ($serverKey.GetValueNames() -notcontains '' -or
                             $serverKey.GetValueKind('') -ne [Microsoft.Win32.RegistryValueKind]::String -or
                             $serverKey.GetValue('') -ne ''))) {
                        throw "A chave de registro do menu de contexto clássico '$serverPath' foi alterada e mantida intacta."
                    }
                }
                Remove-Item -LiteralPath $workaroundPath -Recurse -Force -ErrorAction Stop
            } catch [System.Management.Automation.ItemNotFoundException] {
                # A chave desapareceu antes da limpeza ser concluída.
            }
        }
    } else {
        New-Item -Path $legacyPath -Name InprocServer32 -Value '' -Force -ErrorAction Stop | Out-Null

        if ($null -eq $workaroundKey) {
            # A primeira substituição garante que o CLSID pai exista, então -Force é desnecessário.
            $workaroundKey = New-Item -Path $workaroundPath -ErrorAction Stop
            try {
                New-ItemProperty -LiteralPath $workaroundPath -Name $markerName -Value 1 -PropertyType DWord -ErrorAction Stop | Out-Null
            } catch {
                if ($workaroundKey.ValueCount -eq 0 -and $workaroundKey.SubKeyCount -eq 0) {
                    Remove-Item -LiteralPath $workaroundPath -ErrorAction Stop
                }
                throw
            }
            $ownsWorkaround = $true
        }
        if ($ownsWorkaround -and -not (Test-Path -LiteralPath $serverPath -ErrorAction Stop)) {
            New-Item -Path $serverPath -Value '' -ErrorAction Stop | Out-Null
        } elseif ($ownsWorkaround) {
            $serverKey = Get-Item -LiteralPath $serverPath -ErrorAction Stop
            if ($serverKey.ValueCount -eq 0 -and $serverKey.SubKeyCount -eq 0) {
                # A criação da chave pode dar certo antes de falhar a atribuição do seu valor padrão.
                Set-Item -LiteralPath $serverPath -Value '' -Force -ErrorAction Stop
            }
        }
    }

    $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    Get-Process -Name explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId } |
        ForEach-Object { Stop-Process -Id $_.Id -ErrorAction SilentlyContinue }
}
