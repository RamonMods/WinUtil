function Get-WinUtilAppIcon {
    <#
        .SYNOPSIS
            Retorna o ícone embutido de um app na aba Instalar

        .DESCRIPTION
            Os ícones acompanham o script como PNGs em base64, um por app, tirados de config/icons/<key>.png
            em tempo de compilação, então a aba Instalar não precisa de acesso à rede para desenhá-los e nada
            fica esperando um serviço de favicon.

            Cada ícone é decodificado uma vez em um bitmap congelado, que o WPF pode compartilhar entre
            entradas, threads e janelas. Ele fica na memória pelo resto da sessão e nunca é gravado
            em disco.

        .PARAMETER Key
            A chave do app como escrita em config/applications.json, sem o prefixo WPFInstall.
            Também é o nome do arquivo do ícone.

        .OUTPUTS
            Um bitmap congelado quando o app tem um ícone embutido.
            $null quando o app não tem arquivo de ícone ou ele não pode ser decodificado, para que o chamador
            possa procurar o ícone online.
    #>
    param([Parameter(Mandatory)][string]$Key)

    if ($null -eq $script:WinUtilAppIconCache) {
        $script:WinUtilAppIconCache = @{}
    }
    if ($script:WinUtilAppIconCache.ContainsKey($Key)) {
        return $script:WinUtilAppIconCache[$Key]
    }

    $icon = $null
    $entry = if ($sync.configs.icons) { $sync.configs.icons.PSObject.Properties[$Key] }
    if ($entry) {
        try {
            # Decodificar o quadro diretamente é cerca de um terço mais rápido do que passar pelo BitmapImage
            $stream = [IO.MemoryStream]::new([Convert]::FromBase64String($entry.Value))
            $frame = [Windows.Media.Imaging.BitmapFrame]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $frame.Freeze()
            $stream.Dispose()
            $icon = $frame
        } catch {
            Write-Debug "O ícone embutido de $Key não pôde ser decodificado: $_"
        }
    }

    $script:WinUtilAppIconCache[$Key] = $icon
    return $icon
}
