function Start-WinUtilTabWarmup {
    <#
        .SYNOPSIS
            Constrói as abas que o usuário ainda não abriu, enquanto a interface está ociosa

        .DESCRIPTION
            O conteúdo das abas precisa ser construído na thread da interface, então uma aba que
            ainda está vazia quando é clicada pela primeira vez faz esse clique pagar a construção.
            Enfileirar as construções move esse custo para onde nada está esperando por ele.

            Enfileirado com prioridade de segundo plano em vez de prioridade ociosa. Na prioridade
            ociosa isto nunca rodava até a lista de aplicativos terminar, que é exatamente a janela
            em que uma aba clicada pelo usuário ainda está vazia e custa uma construção inteira para abrir.
    #>

    # Win11ISO fica de fora: construí-la executa a verificação de trabalho existente, que levanta
    # o aviso de retomada enquanto o usuário está em outra aba. Essa verificação pertence à abertura
    # da aba, não ao seu aquecimento.
    $pending = [System.Collections.Queue]::new()
    foreach ($tab in @("Tweaks", "Config", "AppX")) {
        if (-not $sync.InitializedTabs[$tab]) {
            $pending.Enqueue($tab)
        }
    }

    if ($pending.Count -eq 0) {
        return
    }

    $sync.TabWarmupQueue = $pending
    Start-WinUtilBackgroundQueue -Name "TabWarmup" -Queue $pending -Step {
        param($Tab)

        Measure-WinUtilStep -Scope "UI" -Name "aquecer a aba $Tab" -ScriptBlock {
            Initialize-WinUtilTabContent -TabName $Tab -Yield
        }
    }
}
