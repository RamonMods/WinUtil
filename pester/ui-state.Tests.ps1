#===========================================================================
# Testes - Auxiliares de seleção e estado da interface
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    if (-not ("Windows.Visibility" -as [type])) {
        Add-Type @"
namespace Windows
{
    public enum Visibility
    {
        Visible,
        Collapsed
    }
}
"@
    }

    if (-not ("Windows.WindowState" -as [type])) {
        Add-Type @"
namespace Windows
{
    public enum WindowState
    {
        Normal,
        Minimized,
        Maximized
    }
}
"@
    }

    if (-not ("System.Windows.Controls.CheckBox" -as [type])) {
        Add-Type @"
namespace System.Windows.Controls
{
    public class CheckBox
    {
        private bool? isChecked;
        public event System.EventHandler Checked;
        public event System.EventHandler Unchecked;

        public bool? IsChecked
        {
            get { return isChecked; }
            set
            {
                if (isChecked == value) return;
                isChecked = value;
                if (value == true && Checked != null) Checked(this, System.EventArgs.Empty);
                if (value == false && Unchecked != null) Unchecked(this, System.EventArgs.Empty);
            }
        }
    }

    public class Label
    {
        public object Content { get; set; }
    }

    public class WrapPanel
    {
        public object Visibility { get; set; }
    }

    public class StackPanel
    {
        public System.Collections.ArrayList Children { get; private set; }

        public StackPanel()
        {
            Children = new System.Collections.ArrayList();
        }
    }
}
"@
    }

    . (Join-Path $script:repoRoot "functions\private\Update-WinUtilSelections.ps1")
    . (Join-Path $script:repoRoot "functions\private\Reset-WPFCheckBoxes.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFImpex.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFGetInstalled.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFSelectedCheckboxesUpdate.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFButton.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFToggleAllCategories.ps1")

    function Invoke-WPFRunspace {
        param($ArgumentList, $ParameterList, [scriptblock]$ScriptBlock)
    }
    function Invoke-WPFUIThread {
        param([scriptblock]$ScriptBlock, [hashtable]$Parameters, [switch]$Async)
    }
    function Invoke-WinUtilCurrentSystem {
        param($CheckBox)
    }
    function Set-WinUtilTaskbaritem {
        param($state)
    }
    function Test-WinUtilPackageManager {
        param([switch]$winget)
    }
    function Start-WinUtilJob {
        param([string]$Name, [scriptblock]$ScriptBlock, [hashtable]$Parameters, [string]$Description, [switch]$DisableAppList)
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay)
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }

    function script:New-WinUtilFakeCheckBox {
        param([bool]$IsChecked = $false)

        $checkbox = [System.Windows.Controls.CheckBox]::new()
        $checkbox.IsChecked = $IsChecked
        $checkbox
    }

    function script:New-WinUtilFakeCategory {
        param(
            [string]$Label,
            [Windows.Visibility]$Visibility
        )

        $category = [System.Windows.Controls.StackPanel]::new()
        $categoryLabel = [System.Windows.Controls.Label]::new()
        $categoryLabel.Content = $Label
        $wrapPanel = [System.Windows.Controls.WrapPanel]::new()
        $wrapPanel.Visibility = $Visibility

        $null = $category.Children.Add($categoryLabel)
        $null = $category.Children.Add($wrapPanel)

        $category
    }

    function script:New-WinUtilUiStateTestContext {
        $testSync = [Hashtable]::Synchronized(@{
            selectedApps = [System.Collections.Generic.List[string]]::new()
            selectedTweaks = [System.Collections.Generic.List[string]]::new()
            selectedToggles = [System.Collections.Generic.List[string]]::new()
            selectedFeatures = [System.Collections.Generic.List[string]]::new()
            selectedAppx = [System.Collections.Generic.List[string]]::new()
            configs = @{
                applicationsHashtable = @{
                    WPFInstallGit = [pscustomobject]@{
                        Content = "Git"
                    }
                }
                appxHashtable = @{
                    WPFAppxExample = [pscustomobject]@{}
                }
                tweaks = [pscustomobject]@{
                    WPFTweaksTelemetry = [pscustomobject]@{}
                    WPFToggleDarkMode = [pscustomobject]@{}
                }
                feature = [pscustomobject]@{
                    WPFFeatureSandbox = [pscustomobject]@{}
                }
            }
            WPFselectedAppsButton = [pscustomobject]@{
                Content = ""
            }
            selectedAppsstackPanel = [pscustomobject]@{
                Children = [System.Collections.ArrayList]::new()
            }
        })
        $script:sync = $testSync
        $global:sync = $testSync
    }

    function Add-SelectedAppsMenuItem {
        param($name, $key)

        $null = $global:sync.selectedAppsstackPanel.Children.Add([pscustomobject]@{
            Name = $name
            Key = $key
        })
    }
}

Describe "Update-WinUtilSelections" {
    BeforeEach {
        New-WinUtilUiStateTestContext
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    It "adiciona chaves de caixas de seleção importadas às listas de seleção correspondentes" {
        Update-WinUtilSelections @(
            "WPFInstallGit",
            "WPFTweaksTelemetry",
            "WPFToggleDarkMode",
            "WPFFeatureSandbox",
            "WPFAppxExample"
        )

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        @($script:sync.selectedTweaks) | Should -Be @("WPFTweaksTelemetry")
        @($script:sync.selectedToggles) | Should -Be @("WPFToggleDarkMode")
        @($script:sync.selectedFeatures) | Should -Be @("WPFFeatureSandbox")
        @($script:sync.selectedAppx) | Should -Be @("WPFAppxExample")
    }

    It "mantém entradas <Key> repetidas selecionadas apenas uma vez ao substituir seleções" -ForEach @(
        @{ Key = 'WPFInstallGit'; List = 'selectedApps' }
        @{ Key = 'WPFTweaksTelemetry'; List = 'selectedTweaks' }
        @{ Key = 'WPFToggleDarkMode'; List = 'selectedToggles' }
        @{ Key = 'WPFFeatureSandbox'; List = 'selectedFeatures' }
        @{ Key = 'WPFAppxExample'; List = 'selectedAppx' }
    ) {
        Update-WinUtilSelections -flatJson @($Key, $Key) -Replace

        @($script:sync[$List]) | Should -Be @($Key)
    }

    It "desseleciona completamente um ajuste importado repetido quando desmarcado uma vez" {
        Update-WinUtilSelections -flatJson @('WPFTweaksTelemetry', 'WPFTweaksTelemetry') -Replace

        Invoke-WPFSelectedCheckboxesUpdate -type 'Remove' -checkboxName 'WPFTweaksTelemetry'

        @($script:sync.selectedTweaks) | Should -Be @()
    }

    It "desseleciona completamente importações com variação de caixa após a sincronização das caixas de seleção" {
        Update-WinUtilSelections -flatJson @('wpftweakstelemetry', 'WPFTweaksTelemetry') -Replace

        Invoke-WPFSelectedCheckboxesUpdate -type 'Add' -checkboxName 'WPFTweaksTelemetry'
        @($script:sync.selectedTweaks) | Should -Be @('wpftweakstelemetry')

        Invoke-WPFSelectedCheckboxesUpdate -type 'Remove' -checkboxName 'WPFTweaksTelemetry'
        @($script:sync.selectedTweaks) | Should -Be @()
    }

    It "substitui seleções somente após todas as chaves importadas serem validadas" {
        $script:sync.selectedApps.Add("WPFInstallExisting")
        $script:sync.selectedTweaks.Add("WPFTweaksExisting")

        Update-WinUtilSelections -flatJson @(
            "WPFInstallGit",
            "WPFFeatureSandbox"
        ) -Replace

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        @($script:sync.selectedTweaks) | Should -Be @()
        @($script:sync.selectedFeatures) | Should -Be @("WPFFeatureSandbox")
    }

    It "preserva seleções existentes quando uma chave importada não é suportada" {
        $script:sync.selectedApps.Add("WPFInstallExisting")
        $script:sync.selectedTweaks.Add("WPFTweaksExisting")

        {
            Update-WinUtilSelections -flatJson @(
                "WPFInstallGit",
                "NotAWinUtilKey"
            ) -Replace
        } | Should -Throw "Chave de seleção não suportada: 'NotAWinUtilKey'."

        @($script:sync.selectedApps) | Should -Be @("WPFInstallExisting")
        @($script:sync.selectedTweaks) | Should -Be @("WPFTweaksExisting")
        @($script:sync.selectedFeatures) | Should -Be @()
    }

    It "preserva seleções existentes quando uma chave importada não está no catálogo atual" {
        $script:sync.selectedApps.Add("WPFInstallExisting")

        {
            Update-WinUtilSelections -flatJson @(
                "WPFInstallGit",
                "WPFInstallUnknown"
            ) -Replace
        } | Should -Throw "Chave de seleção desconhecida: 'WPFInstallUnknown'."

        @($script:sync.selectedApps) | Should -Be @("WPFInstallExisting")
        @($script:sync.selectedTweaks) | Should -Be @()
        @($script:sync.selectedFeatures) | Should -Be @()
    }
}

Describe "Reset-WPFCheckBoxes com um sync em mudança" {
    It "sobrevive à adição de entradas ao sync durante sua execução" {
        # O aquecimento da aba cria controles em $sync enquanto isso acontece, e definir IsChecked executa
        # manipuladores que também adicionam a ele. Enumerar $sync ao vivo gerava "Collection was modified".
        $global:sync = [hashtable]::Synchronized(@{})
        # o grower precisa realmente mudar de estado, ou seu manipulador nunca é executado e nada cresce
        $sync.selectedApps = [System.Collections.Generic.List[string]]::new()
        $sync.selectedApps.Add("WPFInstallgrower")
        $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()
        $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()
        $sync.selectedAppx = [System.Collections.Generic.List[string]]::new()
        $sync.selectedToggles = [System.Collections.Generic.List[string]]::new()

        # uma caixa de seleção que faz $sync crescer no momento em que é definida, representando os manipuladores reais
        $grower = New-Object System.Windows.Controls.CheckBox
        $grower.Add_Checked({ $sync["grown_$([guid]::NewGuid().ToString('N'))"] = 1 })
        $grower.Add_Unchecked({ $sync["grown_$([guid]::NewGuid().ToString('N'))"] = 1 })
        $sync["WPFInstallgrower"] = $grower

        foreach ($i in 1..40) { $sync["WPFInstallfiller$i"] = (New-Object System.Windows.Controls.CheckBox) }

        { Reset-WPFCheckBoxes -doToggles $true } | Should -Not -Throw
    }
}

Describe "Estado da seleção na importação de Invoke-WPFImpex" {
    BeforeEach {
        New-WinUtilUiStateTestContext
        $script:sync.Form = [pscustomobject]@{}

        Mock Reset-WPFCheckBoxes { }
        Mock Write-Error { }
        Mock Write-WinUtilLog { }
        Mock Show-WinUtilMessage { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    It "substitui seleções e redefine a interface após uma importação válida" {
        $script:sync.selectedApps.Add("WPFInstallExisting")
        $script:sync.selectedTweaks.Add("WPFTweaksExisting")
        $configPath = Join-Path $TestDrive "valid-config.json"
        @(
            "WPFInstallGit",
            "WPFFeatureSandbox"
        ) | ConvertTo-Json | Set-Content -LiteralPath $configPath

        Invoke-WPFImpex -type "import" -Config $configPath

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        @($script:sync.selectedTweaks) | Should -Be @()
        @($script:sync.selectedFeatures) | Should -Be @("WPFFeatureSandbox")
        Should -Invoke -CommandName Reset-WPFCheckBoxes -Times 1 -Exactly -ParameterFilter {
            $doToggles -eq $true
        }
        Should -Invoke -CommandName Write-Error -Times 0 -Exactly
    }

    It "importa seleções legadas suportadas e relata entradas desativadas" {
        $configPath = Join-Path $script:repoRoot "pester\fixtures\legacy-config.json"

        Invoke-WPFImpex -type "import" -Config $configPath

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        @($script:sync.selectedTweaks) | Should -Be @("WPFTweaksTelemetry")
        @($script:sync.selectedFeatures) | Should -Be @("WPFFeatureSandbox")
        Should -Invoke -CommandName Reset-WPFCheckBoxes -Times 1 -Exactly -ParameterFilter {
            $doToggles -eq $true
        }
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Impex" -and
            $Level -eq "WARN" -and
            $Message -eq "Seleções herdadas sem suporte ignoradas: WPFInstallRetired"
        }
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Title -eq "Configuração herdada importada parcialmente" -and
            $Message -like "*WPFInstallRetired*"
        }
        Should -Invoke -CommandName Write-Error -Times 0 -Exactly
    }

    It "ignora metadados de string não relacionados em uma configuração legada" {
        $configPath = Join-Path $TestDrive "legacy-config-with-metadata.json"
        [pscustomobject]@{
            Install = @([pscustomobject]@{ winget = "Git.Git"; choco = "git" })
            WPFInstall = @("WPFInstallGit")
            ExportVersion = "1.0"
        } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $configPath

        Invoke-WPFImpex -type "import" -Config $configPath

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        Should -Invoke -CommandName Reset-WPFCheckBoxes -Times 1 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Impex" -and
            $Message -eq "Estrutura de configuração herdada do WinUtil detectada; achatando o objeto de importação."
        }
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
        Should -Invoke -CommandName Write-Error -Times 0 -Exactly
    }

    It "preserva seleções quando todas as entradas legadas estão desativadas" {
        $script:sync.selectedApps.Add("WPFInstallExisting")
        $configPath = Join-Path $TestDrive "retired-legacy-config.json"
        [pscustomobject]@{
            Install = @([pscustomobject]@{ winget = "Retired.App"; choco = "retired-app" })
            WPFTweaks = @()
            WPFFeature = @()
            WPFInstall = @("WPFInstallRetired")
        } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $configPath

        Invoke-WPFImpex -type "import" -Config $configPath

        @($script:sync.selectedApps) | Should -Be @("WPFInstallExisting")
        Should -Invoke -CommandName Reset-WPFCheckBoxes -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Seleções herdadas sem suporte ignoradas: WPFInstallRetired"
        }
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Title -eq "Configuração herdada sem suporte"
        }
        Should -Invoke -CommandName Write-Error -Times 0 -Exactly
    }

    It "importa grupos de seleção legados sem tratar metadados de Install como uma seleção" {
        $legacyConfigPath = Join-Path $TestDrive "legacy-config.json"
        [ordered]@{
            Install = @(
                [pscustomobject]@{
                    winget = "Git.Git"
                    choco = "git"
                }
            )
            WPFInstall = @("WPFInstallGit")
            WPFTweaks = @("WPFTweaksTelemetry")
            WPFToggle = @("WPFToggleDarkMode")
            WPFFeature = @("WPFFeatureSandbox")
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $legacyConfigPath

        Invoke-WPFImpex -type "import" -Config $legacyConfigPath

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        @($script:sync.selectedTweaks) | Should -Be @("WPFTweaksTelemetry")
        @($script:sync.selectedToggles) | Should -Be @("WPFToggleDarkMode")
        @($script:sync.selectedFeatures) | Should -Be @("WPFFeatureSandbox")
        Should -Invoke -CommandName Write-Error -Times 0 -Exactly
    }

    It "preserva seleções e não redefine a interface após uma importação inválida" {
        $script:sync.selectedApps.Add("WPFInstallExisting")
        $script:sync.selectedTweaks.Add("WPFTweaksExisting")
        $configPath = Join-Path $TestDrive "invalid-config.json"
        @(
            "WPFInstallGit",
            "WPFInstallUnknown"
        ) | ConvertTo-Json | Set-Content -LiteralPath $configPath

        Invoke-WPFImpex -type "import" -Config $configPath

        @($script:sync.selectedApps) | Should -Be @("WPFInstallExisting")
        @($script:sync.selectedTweaks) | Should -Be @("WPFTweaksExisting")
        @($script:sync.selectedFeatures) | Should -Be @()
        Should -Invoke -CommandName Reset-WPFCheckBoxes -Times 0 -Exactly
        Should -Invoke -CommandName Write-Error -Times 1 -Exactly -ParameterFilter {
            $Message -like "Ocorreu um erro durante a importação: *Chave de seleção desconhecida: 'WPFInstallUnknown'.*"
        }
    }
}

Describe "Invoke-WPFSelectedCheckboxesUpdate" {
    BeforeEach {
        New-WinUtilUiStateTestContext
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    It "adiciona cada família de caixas de seleção sem duplicar seleções existentes" {
        Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName "WPFInstallGit"
        Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName "WPFInstallGit"
        Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName "WPFTweaksTelemetry"
        Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName "WPFToggleDarkMode"
        Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName "WPFFeatureSandbox"
        Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName "WPFAppxExample"

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        @($script:sync.selectedTweaks) | Should -Be @("WPFTweaksTelemetry")
        @($script:sync.selectedToggles) | Should -Be @("WPFToggleDarkMode")
        @($script:sync.selectedFeatures) | Should -Be @("WPFFeatureSandbox")
        @($script:sync.selectedAppx) | Should -Be @("WPFAppxExample")
        $script:sync.WPFselectedAppsButton.Content | Should -Be "Aplicativos selecionados: 1"
        $script:sync.selectedAppsstackPanel.Children.Count | Should -Be 1
        $script:sync.selectedAppsstackPanel.Children[0].Key | Should -Be "WPFInstallGit"
    }

    It "remove chaves de caixas de seleção das listas de seleção correspondentes" {
        $script:sync.selectedApps.Add("WPFInstallGit")
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        $script:sync.selectedToggles.Add("WPFToggleDarkMode")
        $script:sync.selectedFeatures.Add("WPFFeatureSandbox")
        $script:sync.selectedAppx.Add("WPFAppxExample")

        Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName "WPFInstallGit"
        Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName "WPFTweaksTelemetry"
        Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName "WPFToggleDarkMode"
        Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName "WPFFeatureSandbox"
        Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName "WPFAppxExample"

        $script:sync.selectedApps.Count | Should -Be 0
        $script:sync.selectedTweaks.Count | Should -Be 0
        $script:sync.selectedToggles.Count | Should -Be 0
        $script:sync.selectedFeatures.Count | Should -Be 0
        $script:sync.selectedAppx.Count | Should -Be 0
        $script:sync.WPFselectedAppsButton.Content | Should -Be "Aplicativos selecionados: 0"
        $script:sync.selectedAppsstackPanel.Children.Count | Should -Be 0
    }
}

Describe "Estado da seleção de Invoke-WPFGetInstalled" {
    BeforeEach {
        New-WinUtilUiStateTestContext

        $script:sync.ProcessRunning = $false
        $script:sync.ChocoRadioButton = [pscustomobject]@{ IsChecked = $false }
        $script:sync.preferences = [pscustomobject]@{ packagemanager = "Winget" }
        $script:sync.WPFInstallGit = New-WinUtilFakeCheckBox
        $dispatcher = [pscustomobject]@{}
        $dispatcher | Add-Member -MemberType ScriptMethod -Name BeginInvoke -Value {
            param($Action, [object[]]$Arguments)
            $Action.DynamicInvoke($Arguments)
        }
        $script:sync.Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        $script:capturedGetInstalledScriptBlock = $null
        $script:capturedGetInstalledParameters = @{}

        Mock Test-WinUtilPackageManager { "installed" }
        Mock Invoke-WinUtilCurrentSystem { @("WPFInstallGit") }
        Mock Set-WinUtilTaskbaritem { }
        Mock Write-WinUtilLog { }
        Mock Write-Warning { }
        Mock Step-WinUtilJob { }
        Mock Invoke-WPFUIThread { $uiParameters = $Parameters; & $ScriptBlock @uiParameters }
        Mock Start-WinUtilJob {
            $script:capturedGetInstalledScriptBlock = $ScriptBlock
            $script:capturedGetInstalledParameters = $Parameters
        }
    }
    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedGetInstalledScriptBlock -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedGetInstalledParameters -Scope Script -ErrorAction SilentlyContinue
    }

    It "atualiza o modelo de aplicativos selecionados, a caixa de seleção, a contagem e o popup" {
        Invoke-WPFGetInstalled -CheckBox "winget"

        $jobParameters = $script:capturedGetInstalledParameters
        & $script:capturedGetInstalledScriptBlock @jobParameters

        @($script:sync.selectedApps) | Should -Be @("WPFInstallGit")
        $script:sync.WPFInstallGit.IsChecked | Should -BeTrue
        $script:sync.WPFselectedAppsButton.Content | Should -Be "Aplicativos selecionados: 1"
        $script:sync.selectedAppsstackPanel.Children.Count | Should -Be 1
        $script:sync.selectedAppsstackPanel.Children[0].Key | Should -Be "WPFInstallGit"
    }

    It "enfileira a detecção como um job com a preferência de gerenciador" {
        Invoke-WPFGetInstalled -CheckBox "winget"

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Detect installed"
        }
        $script:capturedGetInstalledParameters.Checkbox | Should -Be "winget"
        $script:capturedGetInstalledParameters.ManagerPreference | Should -Be "Winget"
    }

    It "permite que uma falha de detecção apareça para que a camada de jobs possa tratá-la" {
        Mock Invoke-WinUtilCurrentSystem { throw "detection failed" }

        Invoke-WPFGetInstalled -CheckBox "winget"
        $jobParameters = $script:capturedGetInstalledParameters

        { & $script:capturedGetInstalledScriptBlock @jobParameters } | Should -Throw "detection failed"
    }
}
