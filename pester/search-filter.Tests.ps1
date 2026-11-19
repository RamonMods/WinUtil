#===========================================================================
# Testes - Auxiliares de busca e filtragem
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

    if (-not ("System.Windows.Controls.CheckBox" -as [type])) {
        Add-Type @"
namespace System.Windows.Controls
{
    public class CheckBox
    {
        public bool? IsChecked { get; set; }
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

    if (-not ("Windows.Controls.Border" -as [type])) {
        Add-Type @"
namespace Windows.Controls
{
    public class Border
    {
        public object Child { get; set; }
        public object Visibility { get; set; }
    }

    public class DockPanel
    {
        public System.Collections.ArrayList Children { get; private set; }
        public object Visibility { get; set; }

        public DockPanel()
        {
            Children = new System.Collections.ArrayList();
        }
    }

    public class StackPanel
    {
        public System.Collections.ArrayList Children { get; private set; }
        public object Visibility { get; set; }

        public StackPanel()
        {
            Children = new System.Collections.ArrayList();
        }
    }

    public class ItemsControl
    {
        public System.Collections.ArrayList Items { get; private set; }
        public object Visibility { get; set; }

        public ItemsControl()
        {
            Items = new System.Collections.ArrayList();
        }
    }

    public class ScrollViewer
    {
        public object Content { get; set; }
    }

    public class Label
    {
        public object Content { get; set; }
        public object ToolTip { get; set; }
        public object Visibility { get; set; }
    }

    public class CheckBox
    {
        public object Content { get; set; }
        public object ToolTip { get; set; }
        public object Visibility { get; set; }
    }
}
"@
    }

    . (Join-Path $script:repoRoot "functions\private\Find-AppsByNameOrDescription.ps1")
    . (Join-Path $script:repoRoot "functions\private\Find-TweaksByNameOrDescription.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilEntryToolTip.ps1")

    function Write-WinUtilLog {
        param($Level, $Component, $Message)
        throw $Message
    }

    function script:New-WinUtilSearchCollection {
        return ,[System.Collections.ArrayList]::new()
    }

    function script:New-WinUtilAppSearchItem {
        param([string]$Tag)

        [pscustomobject]@{
            Tag = $Tag
            Visibility = [Windows.Visibility]::Visible
        }
    }

    function script:New-WinUtilAppCategory {
        param(
            [string]$Label,
            [object[]]$Items
        )

        $labelControl = [pscustomobject]@{
            Content = $Label
            Visibility = [Windows.Visibility]::Visible
        }
        $wrapPanel = [pscustomobject]@{
            Children = New-WinUtilSearchCollection
            Visibility = [Windows.Visibility]::Visible
        }

        foreach ($item in $Items) {
            $null = $wrapPanel.Children.Add($item)
        }

        $children = New-WinUtilSearchCollection
        $null = $children.Add($labelControl)
        $null = $children.Add($wrapPanel)

        [pscustomobject]@{
            Children = $children
            Visibility = [Windows.Visibility]::Visible
        }
    }

    function script:New-WinUtilAppSearchContext {
        param([object[]]$Categories)

        $items = New-WinUtilSearchCollection
        foreach ($category in $Categories) {
            $null = $items.Add($category)
        }

        $script:sync = [Hashtable]::Synchronized(@{
            ItemsControl = [pscustomobject]@{
                Items = $items
            }
            configs = @{
                applicationsHashtable = @{
                    WPFInstallBrowser = [pscustomobject]@{
                        Content = "Firefox"
                        Description = "Fast private browser"
                        Category = "Browsers"
                    }
                    WPFInstallMedia = [pscustomobject]@{
                        Content = "VLC"
                        Description = "Media player"
                        Category = "Multimedia Tools"
                    }
                    WPFInstallLiteral = [pscustomobject]@{
                        Content = "Tool [abc]"
                        Description = "Literal wildcard sample"
                        Category = "Utilities"
                    }
                    WPFInstallEditor = [pscustomobject]@{
                        Content = "Code Editor"
                        Description = "Text editing"
                        Category = "Development"
                    }
                    WPFInstallPowerToys = [pscustomobject]@{
                        Content = "PowerToys"
                        Description = "A collection of system utilities"
                        Category = "Microsoft Tools"
                    }
                }
            }
        })
        $global:sync = $script:sync
    }

    function script:New-WinUtilFakeSearchForm {
        param(
            $TweaksPanel,
            $AppxPanel
        )

        $form = [pscustomobject]@{
            tweakspanel = $TweaksPanel
            appxpanel = $AppxPanel
        }
        $form | Add-Member -MemberType ScriptMethod -Name FindName -Value {
            param($name)

            return $this.$name
        }

        $form
    }

    function script:New-WinUtilTweakLabelItem {
        param(
            [string]$Content,
            [string]$ToolTip = ""
        )

        $item = [Windows.Controls.DockPanel]::new()
        $checkbox = [Windows.Controls.CheckBox]::new()
        $label = [Windows.Controls.Label]::new()
        $label.Content = $Content
        $label.ToolTip = $ToolTip
        $null = $item.Children.Add($checkbox)
        $null = $item.Children.Add($label)
        $item.Visibility = [Windows.Visibility]::Visible
        $item
    }

    function script:New-WinUtilTweakCheckboxItem {
        param(
            [string]$Content,
            [string]$ToolTip = ""
        )

        $item = [Windows.Controls.StackPanel]::new()
        $checkbox = [Windows.Controls.CheckBox]::new()
        $checkbox.Content = $Content
        $checkbox.ToolTip = $ToolTip
        $null = $item.Children.Add($checkbox)
        $item.Visibility = [Windows.Visibility]::Visible
        $item
    }

    function script:New-WinUtilTweakCategory {
        param(
            [string]$Label,
            [object[]]$Items,
            [ValidateSet("ItemsControl", "StackPanel", "ScrollViewer")]
            [string]$ContainerType = "ItemsControl"
        )

        $categoryLabel = [Windows.Controls.Label]::new()
        $categoryLabel.Content = $Label
        $categoryLabel.Visibility = [Windows.Visibility]::Visible

        $itemsControl = [Windows.Controls.ItemsControl]::new()
        $null = $itemsControl.Items.Add($categoryLabel)
        foreach ($item in $Items) {
            $null = $itemsControl.Items.Add($item)
        }

        $dockPanel = [Windows.Controls.DockPanel]::new()
        if ($ContainerType -eq "ItemsControl") {
            $null = $dockPanel.Children.Add($itemsControl)
        } else {
            $stack = [Windows.Controls.StackPanel]::new()
            $categoryItems = @($itemsControl.Items)
            $itemsControl.Items.Clear()
            foreach ($item in $categoryItems) {
                $null = $stack.Children.Add($item)
            }
            if ($ContainerType -eq "ScrollViewer") {
                $scroll = [Windows.Controls.ScrollViewer]::new()
                $scroll.Content = $stack
                $null = $dockPanel.Children.Add($scroll)
            } else {
                $null = $dockPanel.Children.Add($stack)
            }
        }

        $border = [Windows.Controls.Border]::new()
        $border.Child = $dockPanel
        $border.Visibility = [Windows.Visibility]::Visible

        [pscustomobject]@{
            Border = $border
            Label = $categoryLabel
            ItemsControl = $itemsControl
        }
    }

    function script:New-WinUtilTweakPanel {
        param([object[]]$Categories)

        $panel = [pscustomobject]@{
            Children = New-WinUtilSearchCollection
        }

        foreach ($category in $Categories) {
            $null = $panel.Children.Add($category.Border)
        }

        $panel
    }

    function script:New-WinUtilTweakSearchContext {
        param(
            $TweaksPanel,
            $AppxPanel = $null,
            [string]$CurrentTab = "Tweaks"
        )

        $script:sync = [Hashtable]::Synchronized(@{
            currentTab = $CurrentTab
            Form = New-WinUtilFakeSearchForm -TweaksPanel $TweaksPanel -AppxPanel $AppxPanel
        })
        $global:sync = $script:sync
    }

    function script:Remove-WinUtilSearchGlobals {
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Find-AppsByNameOrDescription" {
    AfterEach {
        Remove-WinUtilSearchGlobals
    }

    It "restaura a visibilidade dos aplicativos e respeita o estado recolhido das categorias em uma busca vazia" {
        $browserItem = New-WinUtilAppSearchItem -Tag "WPFInstallBrowser"
        $mediaItem = New-WinUtilAppSearchItem -Tag "WPFInstallMedia"
        $browserItem.Visibility = [Windows.Visibility]::Collapsed
        $mediaItem.Visibility = [Windows.Visibility]::Collapsed

        $collapsedCategory = New-WinUtilAppCategory -Label "+ Browsers" -Items @($browserItem)
        $expandedCategory = New-WinUtilAppCategory -Label "- Media" -Items @($mediaItem)
        $collapsedCategory.Children[1].Visibility = [Windows.Visibility]::Collapsed
        $expandedCategory.Children[1].Visibility = [Windows.Visibility]::Collapsed
        New-WinUtilAppSearchContext -Categories @($collapsedCategory, $expandedCategory)

        Find-AppsByNameOrDescription -SearchString ""

        $collapsedCategory.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $collapsedCategory.Children[0].Visibility | Should -Be ([Windows.Visibility]::Visible)
        $collapsedCategory.Children[1].Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $browserItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $expandedCategory.Children[1].Visibility | Should -Be ([Windows.Visibility]::Visible)
        $mediaItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
    }

    It "mostra aplicativos correspondentes por descrição e oculta categorias sem correspondências" {
        $browserItem = New-WinUtilAppSearchItem -Tag "WPFInstallBrowser"
        $mediaItem = New-WinUtilAppSearchItem -Tag "WPFInstallMedia"
        $editorItem = New-WinUtilAppSearchItem -Tag "WPFInstallEditor"
        $browserCategory = New-WinUtilAppCategory -Label "+ Browsers" -Items @($browserItem, $mediaItem)
        $editorCategory = New-WinUtilAppCategory -Label "- Editors" -Items @($editorItem)
        New-WinUtilAppSearchContext -Categories @($browserCategory, $editorCategory)

        Find-AppsByNameOrDescription -SearchString "private"

        $browserCategory.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $browserCategory.Children[0].Content | Should -Be "- Browsers"
        $browserCategory.Children[1].Visibility | Should -Be ([Windows.Visibility]::Visible)
        $browserItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $mediaItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $editorCategory.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $editorItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    It "corresponde aplicativos por chave de predefinição" {
        $browserItem = New-WinUtilAppSearchItem -Tag "WPFInstallBrowser"
        $mediaItem = New-WinUtilAppSearchItem -Tag "WPFInstallMedia"
        $category = New-WinUtilAppCategory -Label "- Browsers" -Items @($browserItem, $mediaItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -SearchString "WPFInstallBrowser"

        $browserItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $mediaItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $category.Visibility | Should -Be ([Windows.Visibility]::Visible)
    }

    It "trata caracteres curinga como texto literal de busca de aplicativos" {
        $literalItem = New-WinUtilAppSearchItem -Tag "WPFInstallLiteral"
        $mediaItem = New-WinUtilAppSearchItem -Tag "WPFInstallMedia"
        $category = New-WinUtilAppCategory -Label "- Tools" -Items @($literalItem, $mediaItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -SearchString "[abc]"

        $literalItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $mediaItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $category.Visibility | Should -Be ([Windows.Visibility]::Visible)
    }

    It "filtra as etiquetas de categoria pela categoria exata de aplicativo" {
        $utilityItem = New-WinUtilAppSearchItem -Tag "WPFInstallLiteral"
        $powerToysItem = New-WinUtilAppSearchItem -Tag "WPFInstallPowerToys"
        $category = New-WinUtilAppCategory -Label "- Tools" -Items @($utilityItem, $powerToysItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -Categories @("Utilities")

        $utilityItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $powerToysItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $category.Visibility | Should -Be ([Windows.Visibility]::Visible)
    }

    It "mostra aplicativos de todas as categorias selecionadas quando várias etiquetas estão ativas" {
        $utilityItem = New-WinUtilAppSearchItem -Tag "WPFInstallLiteral"
        $powerToysItem = New-WinUtilAppSearchItem -Tag "WPFInstallPowerToys"
        $browserItem = New-WinUtilAppSearchItem -Tag "WPFInstallBrowser"
        $category = New-WinUtilAppCategory -Label "- Tools" -Items @($utilityItem, $powerToysItem, $browserItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -Categories @("Utilities", "Microsoft Tools")

        $utilityItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $powerToysItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $browserItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    It "aplica o texto de busca e o filtro de categoria juntos" {
        $powerToysItem = New-WinUtilAppSearchItem -Tag "WPFInstallPowerToys"
        $literalItem = New-WinUtilAppSearchItem -Tag "WPFInstallLiteral"
        $category = New-WinUtilAppCategory -Label "- Tools" -Items @($powerToysItem, $literalItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -SearchString "PowerToys" -Categories @("Microsoft Tools")

        $powerToysItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $literalItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    It "oculta uma categoria quando o texto de busca não corresponde a nada dentro das categorias selecionadas" {
        $powerToysItem = New-WinUtilAppSearchItem -Tag "WPFInstallPowerToys"
        $category = New-WinUtilAppCategory -Label "- Tools" -Items @($powerToysItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -SearchString "Firefox" -Categories @("Microsoft Tools")

        $powerToysItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $category.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    It "expande uma categoria recolhida que tem correspondências para o filtro selecionado" {
        $powerToysItem = New-WinUtilAppSearchItem -Tag "WPFInstallPowerToys"
        $category = New-WinUtilAppCategory -Label "+ Tools" -Items @($powerToysItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -Categories @("Microsoft Tools")

        $category.Children[0].Content | Should -Be "- Tools"
        $category.Children[1].Visibility | Should -Be ([Windows.Visibility]::Visible)
    }

    It "recolhe novamente uma categoria que expandiu após o filtro ser limpo" {
        $powerToysItem = New-WinUtilAppSearchItem -Tag "WPFInstallPowerToys"
        $category = New-WinUtilAppCategory -Label "+ Tools" -Items @($powerToysItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -Categories @("Microsoft Tools")
        $category.Children[0].Content | Should -Be "- Tools"

        Find-AppsByNameOrDescription -SearchString ""

        $category.Children[0].Content | Should -Be "+ Tools"
        $category.Children[1].Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    It "mantém como está uma categoria que o usuário havia expandido quando o filtro é limpo" {
        $powerToysItem = New-WinUtilAppSearchItem -Tag "WPFInstallPowerToys"
        $category = New-WinUtilAppCategory -Label "- Tools" -Items @($powerToysItem)
        New-WinUtilAppSearchContext -Categories @($category)

        Find-AppsByNameOrDescription -Categories @("Microsoft Tools")
        Find-AppsByNameOrDescription -SearchString ""

        $category.Children[0].Content | Should -Be "- Tools"
        $category.Children[1].Visibility | Should -Be ([Windows.Visibility]::Visible)
    }
}

Describe "Find-TweaksByNameOrDescription" {
    It "restaura categorias recolhidas após busca literal em <ContainerType>" -TestCases @(
        @{ ContainerType = "StackPanel" }
        @{ ContainerType = "ScrollViewer" }
    ) {
        param($ContainerType)
        $match = New-WinUtilTweakLabelItem -Content "Tool [abc]"
        $other = New-WinUtilTweakCheckboxItem -Content "Other tool"
        $category = New-WinUtilTweakCategory -Label "+ Privacy" -Items @($match, $other) -ContainerType $ContainerType
        New-WinUtilTweakSearchContext -TweaksPanel (New-WinUtilTweakPanel -Categories @($category))

        Find-TweaksByNameOrDescription -SearchString "[abc]"
        $match.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $other.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $category.Label.Content | Should -Be "- Privacy"

        Find-TweaksByNameOrDescription -SearchString ""
        $category.Label.Content | Should -Be "+ Privacy"
        $match.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $other.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    AfterEach {
        Remove-WinUtilSearchGlobals
    }

    It "restaura os rótulos das categorias e respeita o estado recolhido das categorias em uma busca vazia" {
        $collapsedItem = New-WinUtilTweakLabelItem -Content "Disable Telemetry" -ToolTip "Stop tracking"
        $expandedItem = New-WinUtilTweakCheckboxItem -Content "Show Extensions" -ToolTip "File extension display"
        $collapsedCategory = New-WinUtilTweakCategory -Label "+ Privacy" -Items @($collapsedItem)
        $expandedCategory = New-WinUtilTweakCategory -Label "- Explorer" -Items @($expandedItem)
        $expandedItem.Visibility = [Windows.Visibility]::Collapsed
        $collapsedCategory.Label.Visibility = [Windows.Visibility]::Collapsed
        $collapsedCategory.Border.Visibility = [Windows.Visibility]::Collapsed
        $expandedCategory.Border.Visibility = [Windows.Visibility]::Collapsed
        $panel = New-WinUtilTweakPanel -Categories @($collapsedCategory, $expandedCategory)
        New-WinUtilTweakSearchContext -TweaksPanel $panel

        Find-TweaksByNameOrDescription -SearchString ""

        $collapsedCategory.Border.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $collapsedCategory.Label.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $collapsedCategory.Label.Content | Should -Be "+ Privacy"
        $collapsedItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $expandedCategory.Border.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $expandedCategory.Label.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $expandedCategory.Label.Content | Should -Be "- Explorer"
        $expandedItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
    }

    It "mostra correspondências de ajustes por dica do rótulo e conteúdo da caixa de seleção" {
        $telemetryItem = New-WinUtilTweakLabelItem -Content "Disable Telemetry" -ToolTip "Stop tracking"
        $extensionsItem = New-WinUtilTweakCheckboxItem -Content "Show Extensions" -ToolTip "File extension display"
        $nonMatchItem = New-WinUtilTweakLabelItem -Content "Enable NumLock" -ToolTip "Keyboard setting"
        $category = New-WinUtilTweakCategory -Label "+ Privacy" -Items @($telemetryItem, $extensionsItem, $nonMatchItem)
        $panel = New-WinUtilTweakPanel -Categories @($category)
        New-WinUtilTweakSearchContext -TweaksPanel $panel

        Find-TweaksByNameOrDescription -SearchString "tracking"

        $category.Border.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $category.Label.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $category.Label.Content | Should -Be "- Privacy"
        $telemetryItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $extensionsItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $nonMatchItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)

        Find-TweaksByNameOrDescription -SearchString "Show Extensions"

        $telemetryItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $extensionsItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $nonMatchItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    It "oculta os painéis de categorias de ajustes quando nenhum item corresponde" {
        $item = New-WinUtilTweakLabelItem -Content "Disable Telemetry" -ToolTip "Stop tracking"
        $category = New-WinUtilTweakCategory -Label "- Privacy" -Items @($item)
        $panel = New-WinUtilTweakPanel -Categories @($category)
        New-WinUtilTweakSearchContext -TweaksPanel $panel

        Find-TweaksByNameOrDescription -SearchString "not-present"

        $category.Border.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $category.Label.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $item.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }

    It "pesquisa no painel AppX quando AppX é a aba atual" {
        $tweakItem = New-WinUtilTweakLabelItem -Content "Disable Telemetry" -ToolTip "Stop tracking"
        $appxItem = New-WinUtilTweakCheckboxItem -Content "Xbox Overlay" -ToolTip "Gaming overlay package"
        $tweakCategory = New-WinUtilTweakCategory -Label "- Privacy" -Items @($tweakItem)
        $appxCategory = New-WinUtilTweakCategory -Label "+ AppX" -Items @($appxItem)
        $tweakPanel = New-WinUtilTweakPanel -Categories @($tweakCategory)
        $appxPanel = New-WinUtilTweakPanel -Categories @($appxCategory)
        New-WinUtilTweakSearchContext -TweaksPanel $tweakPanel -AppxPanel $appxPanel -CurrentTab "AppX"

        Find-TweaksByNameOrDescription -SearchString "overlay"

        $appxCategory.Border.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $appxCategory.Label.Content | Should -Be "- AppX"
        $appxItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $tweakCategory.Border.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $tweakItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
    }

    It "corresponde descrições de caixas de seleção e chaves de predefinição, mas não o rótulo da chave de predefinição" {
        $servicesItem = New-WinUtilTweakCheckboxItem -Content "Services - Set to Manual" -ToolTip (Get-WinUtilEntryToolTip -Description "Reduces the number of svchost.exe processes." -Key "WPFTweaksServices")
        $telemetryItem = New-WinUtilTweakCheckboxItem -Content "Telemetry - Disable" -ToolTip (Get-WinUtilEntryToolTip -Description "Disables Microsoft Telemetry." -Key "WPFTweaksTelemetry")
        $category = New-WinUtilTweakCategory -Label "- Essential Tweaks" -Items @($servicesItem, $telemetryItem)
        $panel = New-WinUtilTweakPanel -Categories @($category)
        New-WinUtilTweakSearchContext -TweaksPanel $panel

        Find-TweaksByNameOrDescription -SearchString "key"

        $servicesItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $telemetryItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $category.Border.Visibility | Should -Be ([Windows.Visibility]::Collapsed)

        Find-TweaksByNameOrDescription -SearchString "set"

        $servicesItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $telemetryItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)

        Find-TweaksByNameOrDescription -SearchString "WPFTweaksTelemetry"

        $servicesItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
        $telemetryItem.Visibility | Should -Be ([Windows.Visibility]::Visible)

        Find-TweaksByNameOrDescription -SearchString "svchost"

        $servicesItem.Visibility | Should -Be ([Windows.Visibility]::Visible)
        $telemetryItem.Visibility | Should -Be ([Windows.Visibility]::Collapsed)
    }
}
