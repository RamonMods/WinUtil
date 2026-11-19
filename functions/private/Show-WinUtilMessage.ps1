function Show-WinUtilMessage {
    <#
    .SYNOPSIS
        Exibe uma caixa de mensagem do WinUtil e retorna o resultado selecionado.

    .DESCRIPTION
        Caixas de mensagem precisam da thread da interface, então esta função faz o marshalling para ela
        e por isso pode ser chamada tanto de um corpo de job quanto de um manipulador de eventos. Todo prompt também é gravado
        no log da sessão, para que o log mostre o que foi perguntado ao usuário e não apenas o que aconteceu depois.

        Sem uma janela não há ninguém para clicar, então nada é exibido. Um modal aberto nesse
        estado nunca retorna e leva o worker junto.
    #>
    param (
        [string]$Message,
        [string]$Title = "Winutil",
        $Button = "OK",
        $Icon = "Information"
    )

    Write-WinUtilLog -Component "Dialog" -Message "$Title : $($Message -replace '\r?\n', ' ')"

    if (-not (Test-WinUtilUIAlive)) {
        # Qualquer coisa com escolha é respondida com a opção que não prossegue, para que um prompt
        # que ninguém viu nunca valha como consentimento
        $unattended = if ("$Button" -eq "OK") { "OK" } else { "No" }
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "Sem janela para perguntar, respondendo '$unattended' para: $Title"
        return $unattended
    }

    return Invoke-WPFUIThread -PassThru -Parameters @{
        Message = $Message
        Title = $Title
        Button = $Button
        Icon = $Icon
    } -ScriptBlock {
        param($Message, $Title, $Button, $Icon)

        [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Icon)
    }
}
