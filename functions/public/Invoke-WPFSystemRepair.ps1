function Invoke-WPFSystemRepair {
    <#
    .SYNOPSIS
        Verifica corrupção do sistema usando SFC e DISM
        Verifica falhas no disco usando o Chkdsk

    .DESCRIPTION
        1. Chkdsk - Verifica erros no disco, que podem causar corrupção de arquivos do sistema, e notifica falhas incipientes no disco
        2. SFC - verifica arquivos protegidos do sistema em busca de corrupção e os corrige
        3. DISM - repara uma imagem corrompida do sistema operacional Windows
    #>

    # SuccessCodes mapeia as saídas não zero que uma etapa trata como sucesso para seus significados. Os códigos
    # são por etapa porque o mesmo número significa coisas diferentes: 1 e 2 são resultados comuns do chkdsk,
    # enquanto 1 do sfc é uma falha, e 3010 é uma imagem reparada apenas no DISM.
    $steps = @(
        @{
            Label = "Verificando o disco em busca de erros"
            Arguments = "/c chkdsk /scan /perf"
            # 3 é omitido: o disco não pôde ser verificado ou apresenta erros que uma verificação online não
            # consegue corrigir, e as etapas seguintes não valem a pena em um disco nesse estado.
            SuccessCodes = @{
                1 = "erros foram encontrados e corrigidos"
                2 = "a limpeza foi realizada ou foi ignorada porque /f não foi informado"
            }
        },
        @{
            Label = "Verificando arquivos protegidos do sistema"
            Arguments = "/c sfc /scannow"
            SuccessCodes = @{}
        },
        @{
            Label = "Reparando a imagem do Windows"
            Arguments = "/c dism /online /cleanup-image /restorehealth"
            SuccessCodes = @{
                3010 = "é necessário reiniciar para que o reparo tenha efeito"
            }
        }
    )

    $completed = 0
    foreach ($step in $steps) {
        Step-WinUtilJob -Status "$($step.Label) ($($completed + 1)/$($steps.Count))" -Percent ([int](($completed / $steps.Count) * 100))
        Write-WinUtilLog -Component "SystemRepair" -Message $step.Label
        # Start-Process não lança exceção em uma saída diferente de zero, portanto, sem isso, uma execução falha do chkdsk, sfc
        # ou dism ainda seria reportada como um reparo concluído
        $process = Start-Process cmd.exe -ArgumentList $step.Arguments -NoNewWindow -Wait -PassThru
        $exitCode = $process.ExitCode

        if ($exitCode -ne 0) {
            if ($step.SuccessCodes.ContainsKey($exitCode)) {
                # Start-WinUtilJob registra a saída WarningRecord tanto no log da sessão quanto
                # no resultado do trabalho, portanto resultados não zero aceitos não podem terminar com uma marca de verificação verde.
                Write-Warning "$($step.Label) concluído: $($step.SuccessCodes[$exitCode])."
            } else {
                throw "$($step.Label) falhou com o código de saída $exitCode."
            }
        }

        $completed++
    }
}
