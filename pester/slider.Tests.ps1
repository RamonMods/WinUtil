#===========================================================================
# Testes - Controles deslizantes movem-se para onde são clicados
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:xaml = [xml](Get-Content -Path (Join-Path $script:repoRoot "xaml\inputXML.xaml") -Raw)
}

Describe "Controles deslizantes" {
    It "vai para o ponto clicado em vez de avançar por etapas" {
        # o WPF deixa IsMoveToPointEnabled desativado por padrão, então um clique na trilha avança por página com
        # LargeChange em vez de mover o controle para o ponteiro
        $sliders = @($script:xaml.SelectNodes('//*[local-name()="Slider"]'))
        $sliders.Count | Should -BeGreaterThan 0

        foreach ($slider in $sliders) {
            $name = $slider.GetAttribute("Name")
            $slider.GetAttribute("IsMoveToPointEnabled") | Should -Be "True" -Because "$name deve seguir o clique"
        }
    }

    It "não avança uma unidade inteira por página" {
        # LargeChange tem 1.0 como padrão. Em um intervalo de 0.75 a 2.0 isso é a maior parte da trilha, então
        # um clique nela alternava entre as duas extremidades.
        foreach ($slider in @($script:xaml.SelectNodes('//*[local-name()="Slider"]'))) {
            $name = $slider.GetAttribute("Name")
            $minimumText = $slider.GetAttribute("Minimum")
            $maximumText = $slider.GetAttribute("Maximum")
            $largeChange = $slider.GetAttribute("LargeChange")

            # um atributo ausente volta como string vazia, o que gera erro na conversão abaixo
            $minimumText | Should -Not -BeNullOrEmpty -Because "$name deve declarar um Minimum"
            $maximumText | Should -Not -BeNullOrEmpty -Because "$name deve declarar um Maximum"
            $minimum = [double]$minimumText
            $maximum = [double]$maximumText

            $largeChange | Should -Not -BeNullOrEmpty -Because "$name deve indicar o quanto uma página avança"
            ([double]$largeChange) | Should -BeLessOrEqual (($maximum - $minimum) / 2) -Because "$name avança uma quantidade razoável"
        }
    }

    It "mantém os passos de escala da fonte nas marcas que desenha" {
        $slider = $script:xaml.SelectSingleNode('//*[local-name()="Slider"][@Name="FontScalingSlider"]')

        $slider | Should -Not -BeNullOrEmpty
        $slider.GetAttribute("IsSnapToTickEnabled") | Should -Be "True"

        # ambos ausentes comparariam duas strings vazias e passariam exatamente na regressão que este
        # teste existe para detectar
        $tickFrequency = $slider.GetAttribute("TickFrequency")
        $tickFrequency | Should -Not -BeNullOrEmpty -Because "o controle deslizante deve declarar o espaçamento entre marcas"
        $slider.GetAttribute("SmallChange") | Should -Be $tickFrequency
    }
}
