BeforeAll {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    foreach ($file in @(
        "functions/private/Initialize-InstallAppEntries.ps1",
        "functions/private/Get-WinUtilAppIcon.ps1",
        "functions/private/Get-WinUtilAppEntryHandlers.ps1",
        "functions/private/Get-WinUtilAppEntryFromElement.ps1",
        "functions/private/Get-WinUtilEntryToolTip.ps1",
        "functions/public/Invoke-WPFRunspace.ps1"
    )) {
        . (Join-Path $repoRoot $file)
    }
    function Invoke-WPFSelectedCheckboxesUpdate { param($type, $checkboxName) }

    # PNG transparente de 1x1
    $script:pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
}

Describe "Entradas de aplicativos" {
    BeforeEach {
        $script:WinUtilAppIconCache = $null
        $script:sync = [Hashtable]::Synchronized(@{
            Form = [Windows.Window]::new()
            configs = @{
                applicationsHashtable = @{
                    WPFInstallTestApp = [pscustomobject]@{ content = "Test app"; description = "Test"; link = "https://example.com/"; foss = $false }
                }
                icons = [pscustomobject]@{ TestApp = $script:pixel }
            }
            selectedApps = @()
        })
        $script:panel = [Windows.Controls.WrapPanel]::new()
        Mock Invoke-WPFRunspace { throw "Entries must not occupy the shared job pool" }
    }

    AfterEach {
        if ($script:sync.Form) { $script:sync.Form.Close() }
    }

    Context "com um ícone incorporado" {
        It "desenha o ícone como um bitmap congelado sem download" {
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp
            $content = $checkbox.Content
            $logo = $content.Children[0].Child.Children[1]

            $script:panel.Children.Count | Should -Be 1
            $script:panel.Children[0].Tag | Should -Be "WPFInstallTestApp"
            $content.Children[1].Text | Should -Be "Test app"
            $logo.Source | Should -BeOfType ([Windows.Media.Imaging.BitmapSource])
            $logo.Source.IsFrozen | Should -BeTrue
            $logo.Source.Decoder.GetType().Name | Should -Be "PngBitmapDecoder"
            $content.Children[0].Child.Children[0].Visibility | Should -Be "Collapsed"
            Should -Invoke Invoke-WPFRunspace -Times 0
        }

        It "decodifica cada ícone uma vez e o compartilha entre as entradas" {
            $script:sync.configs.applicationsHashtable.WPFInstallOther = $script:sync.configs.applicationsHashtable.WPFInstallTestApp
            $first = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp
            $second = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp

            [object]::ReferenceEquals($first.Content.Children[0].Child.Children[1].Source, $second.Content.Children[0].Child.Children[1].Source) | Should -BeTrue
        }

        It "retorna as caixas de seleção na ordem das chaves e posiciona cada cartão" {
            foreach ($name in "B", "C") {
                $script:sync.configs.applicationsHashtable["WPFInstall$name"] = [pscustomobject]@{ content = "App $name"; description = ""; link = ""; foss = $false }
            }
            $checkBoxes = @(Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallC, WPFInstallTestApp, WPFInstallB)

            $checkBoxes.Tag | Should -Be @("WPFInstallC", "WPFInstallTestApp", "WPFInstallB")
            @($script:panel.Children.Tag) | Should -Be @("WPFInstallC", "WPFInstallTestApp", "WPFInstallB")
        }

        It "mantém intactos os nomes que precisam de escape" {
            $script:sync.configs.applicationsHashtable.WPFInstallTestApp.content = 'R&D "Tool" <beta>'
            $script:sync.configs.applicationsHashtable.WPFInstallTestApp.description = "Fast & `"free`"`nsecond line"
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp

            $checkbox.Content.Children[1].Text | Should -Be 'R&D "Tool" <beta>'
            $script:panel.Children[0].ToolTip | Should -Be "Fast & `"free`"`nsecond line`n`nPreset key: WPFInstallTestApp"
        }

        It "marca aplicativos livres e de código aberto apenas com o selo no canto" {
            $script:sync.configs.applicationsHashtable.WPFInstallB = [pscustomobject]@{ content = "Free app"; description = ""; link = ""; foss = $true }
            Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp, WPFInstallB | Out-Null

            $script:panel.Children[0].Child.Children.Count | Should -Be 1
            $script:panel.Children[1].Child.Children.Count | Should -Be 2
            $script:panel.Children[1].Child.Children[1] | Should -BeOfType ([Windows.Controls.Viewbox])
        }

        It "marca um aplicativo que já estava selecionado" {
            $script:sync.selectedApps = @("WPFInstallTestApp")
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp

            $checkbox.IsChecked | Should -BeTrue
        }

        It "não precisa de manipulador próprio: os manipuladores compartilhados do painel de categoria detectam a mudança da caixa de seleção" {
            $handlers = Get-WinUtilAppEntryHandlers
            $script:panel.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $handlers.Checked)
            $script:panel.AddHandler([Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $handlers.Unchecked)
            Mock Invoke-WPFSelectedCheckboxesUpdate { }
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp

            $checkbox.IsChecked = $true
            $script:panel.Children[0].ReadLocalValue([Windows.Controls.Border]::BackgroundProperty) | Should -Not -Be ([Windows.DependencyProperty]::UnsetValue)
            $checkbox.IsChecked = $false

            Should -Invoke Invoke-WPFSelectedCheckboxesUpdate -Times 1 -Exactly -ParameterFilter { $type -eq "Add" -and $checkboxName -eq "WPFInstallTestApp" }
            Should -Invoke Invoke-WPFSelectedCheckboxesUpdate -Times 1 -Exactly -ParameterFilter { $type -eq "Remove" -and $checkboxName -eq "WPFInstallTestApp" }
            $script:panel.Children[0].ReadLocalValue([Windows.Controls.Border]::BackgroundProperty) | Should -Be ([Windows.DependencyProperty]::UnsetValue)
        }
    }

    Context "sem um ícone incorporado" {
        It "recorre ao serviço de favicon para um aplicativo sem arquivo de ícone" {
            $script:sync.configs.icons = [pscustomobject]@{}
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp
            $logo = $checkbox.Content.Children[0].Child.Children[1]

            $logo.Source | Should -BeOfType ([Windows.Media.Imaging.BitmapImage])
            $logo.Source.CreateOptions | Should -Be ([Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache)
            $logo.Source.UriSource.AbsoluteUri | Should -Be "https://www.google.com/s2/favicons?sz=64&domain_url=https%3A%2F%2Fexample.com%2F"
            Should -Invoke Invoke-WPFRunspace -Times 0
        }

        It "recorre ao serviço de favicon quando um ícone incorporado não pode ser decodificado" {
            $script:sync.configs.icons = [pscustomobject]@{ TestApp = "bm90IGEgcG5n" }
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp

            $checkbox.Content.Children[0].Child.Children[1].Source.UriSource.AbsoluteUri | Should -BeLike "https://www.google.com/s2/favicons*"
        }

        It "mostra a letra como alternativa quando o WPF relata falha de download" {
            $script:sync.configs.icons = [pscustomobject]@{}
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp
            $icon = $checkbox.Content.Children[0].Child
            $logo = $icon.Children[1]
            $constructor = [Windows.ExceptionRoutedEventArgs].GetConstructors(
                [Reflection.BindingFlags]'Instance, NonPublic')[0]
            $failureEvent = $constructor.Invoke(@([Windows.Controls.Image]::ImageFailedEvent, $logo, [Exception]::new("Download failed")))
            $logo.RaiseEvent($failureEvent)

            $logo.Visibility | Should -Be "Collapsed"
            $icon.Children[0].Visibility | Should -Be "Visible"
        }

        It "mantém a letra como alternativa para aplicativos sem site" {
            $script:sync.configs.icons = [pscustomobject]@{}
            $script:sync.configs.applicationsHashtable.WPFInstallTestApp.link = $null
            $checkbox = Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys WPFInstallTestApp
            $icon = $checkbox.Content.Children[0].Child

            $icon.Children[0].Text | Should -Be "T"
            $icon.Children[0].Visibility | Should -Be "Visible"
            $icon.Children[1].Source | Should -BeNullOrEmpty
        }
    }

    Context "o conjunto de ícones incluído" {
        BeforeAll {
            $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
            $script:applicationKeys = (Get-Content (Join-Path $script:repoRoot "config/applications.json") -Raw | ConvertFrom-Json).PSObject.Properties.Name
            $script:iconFiles = Get-ChildItem (Join-Path $script:repoRoot "config/icons") -File
            # O que Compile.ps1 incorpora: nome do arquivo de ícone -> base64
            $embedded = [ordered]@{}
            foreach ($file in $script:iconFiles) { $embedded[$file.BaseName] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName)) }
            $script:embeddedIcons = [pscustomobject]$embedded
        }

        It "tem um arquivo de ícone nomeado após cada aplicativo ao qual pertence" {
            $orphans = $script:iconFiles | Where-Object { $_.Extension -ne ".png" -or $script:applicationKeys -cnotcontains $_.BaseName } | ForEach-Object { $_.Name }
            $orphans | Should -BeNullOrEmpty
        }

        It "tem um ícone de 48px de no máximo 8 KB para cada aplicativo, para que o script permaneça pequeno" {
            $script:sync.configs.icons = $script:embeddedIcons
            $problems = foreach ($key in $script:applicationKeys) {
                $file = $script:iconFiles | Where-Object { $_.BaseName -ceq $key }
                if (-not $file) { "$key has no config/icons/$key.png (add one with tools/New-WinUtilIcon.ps1)"; continue }
                if ($file.Length -gt 8KB) { "$key.png is $([int]($file.Length / 1KB)) KB; keep icons under 8 KB (tools/New-WinUtilIcon.ps1 writes a 48px icon)" }
                $icon = Get-WinUtilAppIcon -Key $key
                if ($icon -isnot [Windows.Media.Imaging.BitmapSource]) { "$key.png could not be decoded" }
                elseif ($icon.PixelWidth -ne 48 -or $icon.PixelHeight -ne 48) { "$key.png is $($icon.PixelWidth)x$($icon.PixelHeight), not 48x48" }
            }
            $problems | Should -BeNullOrEmpty
        }

        It "constrói a entrada de cada aplicativo em uma única análise" {
            $applications = Get-Content (Join-Path $script:repoRoot "config/applications.json") -Raw | ConvertFrom-Json
            $hashtable = @{}
            foreach ($property in $applications.PSObject.Properties) { $hashtable["WPFInstall$($property.Name)"] = $property.Value }
            $script:sync.configs.applicationsHashtable = $hashtable
            $script:sync.configs.icons = $script:embeddedIcons

            $checkBoxes = @(Initialize-InstallAppEntries -TargetElement $script:panel -AppKeys @($hashtable.Keys))

            $checkBoxes.Count | Should -Be $hashtable.Count
            $script:panel.Children.Count | Should -Be $hashtable.Count
        }
    }
}

Describe "Auxiliar de geração de ícones" {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
        $script:iconHelperSource = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "tools/New-WinUtilIcon.ps1"
    }

    BeforeEach {
        $script:iconFixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $toolsFolder = Join-Path $script:iconFixtureRoot "tools"
        $configFolder = Join-Path $script:iconFixtureRoot "config"
        New-Item -ItemType Directory -Path $toolsFolder, $configFolder -Force | Out-Null
        $script:iconHelper = Join-Path $toolsFolder "New-WinUtilIcon.ps1"
        Copy-Item -LiteralPath $script:iconHelperSource -Destination $script:iconHelper
        Set-Content -LiteralPath (Join-Path $configFolder "applications.json") -Value '{"brave": {}}'
        $script:iconInput = Join-Path $script:iconFixtureRoot "input.png"
        $bitmap = [Drawing.Bitmap]::new(2, 2)
        try {
            $bitmap.Save($script:iconInput, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bitmap.Dispose()
        }
    }

    It "usa a capitalização da chave do catálogo para um ícone recém-gerado" {
        & $script:iconHelper -Key "Brave" -Path $script:iconInput

        $icons = @(Get-ChildItem -LiteralPath (Join-Path $script:iconFixtureRoot "config/icons") -File)
        $icons.Count | Should -Be 1
        $icons[0].Name | Should -BeExactly "brave.png"
    }

    It "rejeita uma chave desconhecida antes de criar um ícone" {
        { & $script:iconHelper -Key "not-in-catalog" -Path $script:iconInput } |
            Should -Throw "'not-in-catalog' não é uma chave em config/applications.json."

        Test-Path -LiteralPath (Join-Path $script:iconFixtureRoot "config/icons") | Should -BeFalse
    }
}
