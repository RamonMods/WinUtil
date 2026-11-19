#===========================================================================
# Testes - Inicialização lenta de abas

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Measure-WinUtilStep.ps1")

    function Test-WinUtilUIAlive { $null -ne $sync.Form -and $null -ne $sync.Form.Dispatcher }

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Invoke-WPFUIElements {
        param($configVariable, [string]$targetGridName, [int]$columncount)
    }
    function Invoke-WinUtilISOCheckExistingWork { }
    function Initialize-WinUtilInstallTabControls { }
    function Reset-WPFCheckBoxes { param([bool]$doToggles) }

    . (Join-Path $script:repoRoot "functions\public\Initialize-WPFUI.ps1")
    . (Join-Path $script:repoRoot "functions\private\Initialize-WinUtilTabContent.ps1")
}

Describe "Initialize-WinUtilTabContent" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                appnavigation = [pscustomobject]@{}
                tweaks = [pscustomobject]@{}
                feature = [pscustomobject]@{}
                appx = [pscustomobject]@{}
            }
        })

        Mock Invoke-WPFUIElements { }
        Mock Initialize-WPFUI { }
        Mock Reset-WPFCheckBoxes { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "inicializa a aba Instalar uma vez" {
        Initialize-WinUtilTabContent -TabName "Install"
        Initialize-WinUtilTabContent -TabName "Install"


        Should -Invoke -CommandName Initialize-WPFUI -Times 1 -Exactly -ParameterFilter {
            $TargetGridName -eq "appscategory"
        }
        Should -Invoke -CommandName Initialize-WPFUI -Times 1 -Exactly -ParameterFilter {
            $TargetGridName -eq "appspanel"
        }
        $script:sync.InitializedTabs["Install"] | Should -BeTrue
    }

    It "deixa a navegação de aplicativos para Initialize-WPFUI para que seus botões mantenham os handlers" {
        # Renderizá-la também aqui criava a navegação duas vezes. A segunda passagem limpava os
        # controles da primeira, e como a verificação de "já conectado" era pelo nome, os
        # substitutos contavam como conectados e nunca recebiam um handler de clique, então Instalar e
        # Desinstalar não faziam absolutamente nada.
        Initialize-WinUtilTabContent -TabName "Install"

        Should -Invoke -CommandName Invoke-WPFUIElements -Times 0 -Exactly -ParameterFilter {
            $targetGridName -eq "appscategory"
        }
    }

    It "inicializa uma vez as abas diferidas baseadas em configurações" {
        Initialize-WinUtilTabContent -TabName "Tweaks"
        Initialize-WinUtilTabContent -TabName "Config"
        Initialize-WinUtilTabContent -TabName "AppX"
        Initialize-WinUtilTabContent -TabName "Tweaks"
        Initialize-WinUtilTabContent -TabName "Config"
        Initialize-WinUtilTabContent -TabName "AppX"

        Should -Invoke -CommandName Invoke-WPFUIElements -Times 1 -Exactly -ParameterFilter {
            $targetGridName -eq "tweakspanel" -and $columncount -eq 2
        }
        Should -Invoke -CommandName Invoke-WPFUIElements -Times 1 -Exactly -ParameterFilter {
            $targetGridName -eq "featurespanel" -and $columncount -eq 2
        }
        Should -Invoke -CommandName Invoke-WPFUIElements -Times 1 -Exactly -ParameterFilter {
            $targetGridName -eq "appxpanel" -and $columncount -eq 2
        }
    }

    It "reaplica as seleções das caixas de seleção após criar os controles de uma aba" {
        # os controles recém-criados começam desmarcados, então uma importação ou uma predefinição precisa alcançá-los
        Initialize-WinUtilTabContent -TabName "Tweaks"

        Should -Invoke -CommandName Reset-WPFCheckBoxes -Times 1 -Exactly -ParameterFilter {
            $doToggles -eq $true
        }
    }

    It "não reaplica as seleções das caixas de seleção em uma aba já criada" {
        Initialize-WinUtilTabContent -TabName "Tweaks"
        Initialize-WinUtilTabContent -TabName "Tweaks"

        Should -Invoke -CommandName Reset-WPFCheckBoxes -Times 1 -Exactly
    }

    It "verifica se existe trabalho Win11ISO quando a aba é inicializada" {
        Add-Type -AssemblyName WindowsBase
        $dispatcher = [pscustomobject]@{}
        $dispatcher | Add-Member -MemberType ScriptMethod -Name BeginInvoke -Value {
            param($priority, $action)
            $action.Invoke()
        }
        $script:sync.Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        Mock Invoke-WinUtilISOCheckExistingWork { }

        Initialize-WinUtilTabContent -TabName "Win11ISO"
        Initialize-WinUtilTabContent -TabName "Win11ISO"

        Should -Invoke -CommandName Invoke-WinUtilISOCheckExistingWork -Times 1 -Exactly
        $script:sync.InitializedTabs["Win11ISO"] | Should -BeTrue
    }
}

Describe "Initialize-WPFUI" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                appnavigation = [pscustomobject]@{}
            }
        })

        Mock Invoke-WPFUIElements { throw "App category rendered" }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "renderiza a navegação de aplicativos pelo destino da categoria de aplicativos" {
        { Initialize-WPFUI -TargetGridName "appscategory" } | Should -Throw "App category rendered"

        Should -Invoke -CommandName Invoke-WPFUIElements -Times 1 -Exactly -ParameterFilter {
            $configVariable -eq $script:sync.configs.appnavigation -and
            $targetGridName -eq "appscategory" -and
            $columncount -eq 1
        }
    }
}

Describe "Conexão lenta de abas na inicialização" {
    It "não cria conteúdo de aba antes da primeira renderização" {
        # A inicialização saiu de main.ps1 e foi para a thread da interface. Nada mais é criado
        # antecipadamente: Invoke-WPFTab cria a aba que seleciona, e o aquecimento faz o restante.
        $uiScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1") -Raw

        $uiScript | Should -Match 'Invoke-WPFTab "WPFTab1BT"'
        $uiScript | Should -Not -Match 'targetGridName "tweakspanel"'
        $uiScript | Should -Not -Match 'targetGridName "featurespanel"'
        $uiScript | Should -Not -Match 'targetGridName "appxpanel"'
    }

    It "inicializa o conteúdo da aba quando uma aba é selecionada" {
        $tabScript = Get-Content -Path (Join-Path $script:repoRoot "functions\public\Invoke-WPFTab.ps1") -Raw

        $tabScript | Should -Match 'Initialize-WinUtilTabContent -TabName \$sync\.currentTab'
    }

    It "vincula cliques de botões gerados quando os painéis lentos são renderizados" {
        $rendererScript = Get-Content -Path (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIElements.ps1") -Raw
        $mainScript = Get-Content -Path (Join-Path $script:repoRoot "scripts\main.ps1") -Raw

        $rendererScript | Should -Match '(?s)"Button"\s*\{.*\$button\.Add_Click\(\{.*Invoke-WPFButton \$Sender\.name'
        $rendererScript | Should -Match '\$sync\.Buttons\.Add\(\$button\.Name\)'
        # A verificação de "já conectado" mudou para a thread da interface junto com o restante da inicialização
        $uiScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1") -Raw
        $uiScript | Should -Match '\$alreadyWired'
    }

    It "vincula links de documentação gerados quando os painéis lentos são renderizados" {
        $rendererScript = Get-Content -Path (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIElements.ps1") -Raw
        $mainScript = Get-Content -Path (Join-Path $script:repoRoot "scripts\main.ps1") -Raw

        $rendererScript | Should -Match '(?s)if \(\$entryInfo\.Link\).*\$textBlock\.Add_MouseUp\(\{.*Start-Process \$Sender\.ToolTip -ErrorAction Stop'
        $mainScript | Should -Not -Match '\.Name\.EndsWith\("Link"\)'
    }

    It "verifica se existe um ScrollViewer externo antes de aninhar um ScrollViewer interno" {
        $rendererScript = Get-Content -Path (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIElements.ps1") -Raw

        $rendererScript | Should -Match '\$hasOuterScrollViewer'
        $rendererScript | Should -Match 'if\s*\(\$hasOuterScrollViewer\)'
    }

    It "reaplica a busca ao vivo após a conclusão da renderização dos controles da aba" {
        $rendererScript = Get-Content -Path (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIElements.ps1") -Raw
        $tabScript = Get-Content -Path (Join-Path $script:repoRoot "functions\public\Invoke-WPFTab.ps1") -Raw

        $rendererScript | Should -Match 'Find-TweaksByNameOrDescription -SearchString \$sync\.SearchBar\.Text'
        $tabScript | Should -Match 'Find-TweaksByNameOrDescription -SearchString \$searchText'
        $tabScript | Should -Match 'Find-AppsByNameOrDescription -SearchString \$searchText'
    }

    It "passa o frame de yield para o callback do dispatcher" {
        $rendererScript = Get-Content -Path (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIElements.ps1") -Raw

        $rendererScript | Should -Match '(?s)DispatcherOperationCallback\]\s*\{\s*param\(\$dispatcherFrame\).*\$dispatcherFrame\.Continue = \$false.*\},\s*\$frame\)'
    }
}
