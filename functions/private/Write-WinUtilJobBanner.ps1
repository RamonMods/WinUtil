function Write-WinUtilJobBanner {
    <#
        .SYNOPSIS
            Escreve a linha em caixa de início, conclusão ou falha que um job imprime no console

        .DESCRIPTION
            Um único lugar decide como uma operação em execução aparece no terminal, para que cada
            fluxo de trabalho se anuncie da mesma forma em vez de desenhar sua própria caixa.
            Chamado por Start-WinUtilJob, não pelos corpos dos jobs.

        .PARAMETER Message
            A linha a colocar na caixa, por exemplo "Instalando aplicativos".

        .PARAMETER Level
            INFO para um banner normal, ERROR para colori-lo como uma falha.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "ERROR")]
        [string]$Level = "INFO"
    )

    # Uma linha de progresso é reescrita no mesmo lugar e deixada aberta, então a caixa seria desenhada sobre ela
    Complete-WinUtilConsoleProgress

    # Quebrada em linhas, porque uma falha que lista vários pacotes desenharia uma caixa mais
    # larga que o console
    $width = 76
    $words = $Message -split '\s+'
    $lines = [System.Collections.Generic.List[string]]::new()
    $current = ""
    foreach ($word in $words) {
        if ($current.Length -gt 0 -and ($current.Length + 1 + $word.Length) -gt $width) {
            $lines.Add($current)
            $current = $word
        } else {
            $current = if ($current.Length -eq 0) { $word } else { "$current $word" }
        }
    }
    if ($current.Length -gt 0) { $lines.Add($current) }

    $longest = ($lines | Measure-Object -Property Length -Maximum).Maximum
    $border = "=" * ($longest + 6)
    $colour = if ($Level -eq "ERROR") { "Red" } else { "Cyan" }

    Write-WinUtilHost ""
    Write-WinUtilHost $border -ForegroundColor $colour
    foreach ($line in $lines) {
        Write-WinUtilHost ("-- {0}$(' ' * ($longest - $line.Length)) --" -f $line) -ForegroundColor $colour
    }
    Write-WinUtilHost $border -ForegroundColor $colour
}
