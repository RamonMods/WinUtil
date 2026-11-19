# SPEC.md

Contrato do projeto WinUtil — o que o projeto é, como é construído e como funciona. Escrito para qualquer pessoa, humana ou IA, que precise entender o projeto em si.

O `AGENTS.md` na raiz do repositório aponta para cá em relação a esses fatos e, separadamente, cobre como um agente deve se comportar enquanto trabalha neste repositório. Este arquivo não muda conforme quem está lendo.

## Contexto Do Projeto

WinUtil é um utilitário de Windows em PowerShell com interface WPF. O repositório é mantido como código modular, mas o artefato distribuído é um único script PowerShell compilado.

### Stack

- Linguagem: Windows PowerShell / PowerShell.
- Interface: WPF via `xaml/inputXML.xaml`.
- Configuração: arquivos JSON em `config/`.
- Testes: testes Pester em `pester/`.
- Lint: PowerShell Script Analyzer com configurações em `lint/PSScriptAnalyser.ps1`.
- Documentação: site Astro + Starlight em `docs/`, compilado de forma independente do `Compile.ps1` (com seu próprio `package.json`/`node_modules`).
- Artefato de release: `winutil.ps1` gerado na raiz.

### Estrutura Do Repositório

- `Compile.ps1`: script de build que cria o `winutil.ps1`.
- `scripts/start.ps1`: trecho de inicialização/bootstrap usado no começo do script compilado.
- `scripts/main.ps1`: ponto de entrada principal anexado ao final do script compilado.
- `functions/public/`: funções PowerShell públicas/de interface.
- `functions/private/`: funções PowerShell auxiliares internas.
- `config/`: configuração JSON consumida em tempo de compilação e embutida em `$sync.configs`.
- `xaml/inputXML.xaml`: marcação da interface WPF embutida no script compilado.
- `tools/autounattend.xml`: XML de instalação autônoma embutido para fluxos de ISO do Windows.
- `pester/`: testes Pester para checagens de configuração e de funções.
- `lint/PSScriptAnalyser.ps1`: configurações do PowerShell Script Analyzer.
- `tools/title-screen/`: projeto uv que captura os temas Claro e Escuro do WinUtil e gera a composição da tela de título.
- `docs/`: site de documentação Astro + Starlight, com seu próprio `package.json` e build independente do `Compile.ps1`.
- `winutil.ps1`: artefato de build gerado e ignorado.

## Objetivos

- Fornecer um utilitário de Windows em script único que possa ser iniciado a partir do PowerShell.
- Manter o desenvolvimento modular o suficiente para que colaboradores trabalhem de forma independente em funções, configuração, interface, documentação e ferramentas.
- Tornar os fluxos de instalação, ajuste, recursos, reparo, atualização e ISO descobríveis pela interface WPF.
- Manter listas e opções comuns declarativas no JSON de configuração sempre que possível.
- Preservar um processo de compilação repetível, para que builds locais e builds do GitHub Actions produzam o script distribuível a partir das mesmas entradas.

## Não Objetivos

- `winutil.ps1` não é mantido à mão.
- O projeto não é estruturado como um módulo PowerShell em tempo de execução.
- A interface gráfica não é uma aplicação desktop empacotada separadamente no caminho normal de release deste repositório.
- Arquivos gerados não devem ser revisados como mudanças de código-fonte.

## Modelo De Build

O `Compile.ps1` combina os códigos-fonte do repositório em `winutil.ps1` nesta ordem:

1. Lê `scripts/start.ps1` e substitui `#{replaceme}` pela data de build atual no formato `yy.MM.dd`.
2. Anexa todos os arquivos em `functions/` recursivamente.
3. Converte cada arquivo `config/*.json` em objetos embutidos em `$sync.configs`.
4. Trata `config/applications.json` como caso especial, para que as chaves recebam o prefixo `WPFInstall` na configuração compilada.
5. Embute `xaml/inputXML.xaml` em `$inputXML`.
6. Embute `tools/autounattend.xml` em `$WinUtilAutounattendXml`.
7. Anexa `scripts/main.ps1`.
8. Grava o resultado no `winutil.ps1` da raiz.

Como o script final é concatenado, o código não pode depender de importações de módulo em tempo de execução nem de dot-sourcing relativo à origem, a menos que o script compilado também contenha o código/dados necessários.

## Modelo De Execução

- O WinUtil roda em PowerShell no Windows e usa WPF para a interface.
- O estado mutável compartilhado fica em `$sync`, incluindo configurações, referências a elementos de interface, estado de runspace, seleções e progresso.
- Operações longas usam runspaces ou padrões assíncronos já existentes, para que a interface continue responsiva.
- Ações do usuário que optam pela fila de jobs rodam uma por vez, com as entradas que selecionaram. O trabalho enfileirado pode ser reordenado ou cancelado, pausa durante a confirmação de fechamento e é descartado quando a janela fecha. Jobs de ISO e de USB continuam se recusando a entrar na fila.
- Atualizações de interface vindas de trabalho em segundo plano são despachadas de volta para a thread de interface do WPF.
- Cada runspace registra em log no arquivo de sessão com data e hora em `%LocalAppData%\winutil\logs`, por meio de `Write-WinUtilLog`, que compartilha um único escritor via `$sync`. A saída dos jobs e os avisos, erros e saídas de `Write-Host` do runspace da interface são recolhidos nesse arquivo; saídas apenas de console, como banners e progresso, usam `Write-WinUtilHost`.
- Recursos declarativos, como aplicativos, ajustes, predefinições, provedores de DNS e navegação, ficam em `config/*.json` a menos que seja necessário código.

## Contrato De Interface E Eventos

- O layout da interface fica em `xaml/inputXML.xaml`.
- Controles WPF nomeados são descobertos e armazenados em `$sync`.
- O conteúdo da janela maximizada é ajustado à área de trabalho do monitor atual por `Update-WinUtilWindowInsets`, usando limites nativos convertidos para unidades WPF. Eventos da interface agrupam atualizações no dispatcher após mudanças de janela ou de DPI.
- A ligação de botões/ações segue uma convenção de nomes: um elemento chamado como `WPFThingButton` mapeia para uma função chamada como `Invoke-WPFThingButton`.

## Contrato De Configuração

- Os arquivos de configuração devem continuar sendo JSON válido e compilar sem erros por `ConvertFrom-Json`.
- `config/dns.json` coloca provedores sem filtro na seleção Mais Rápido com `BenchmarkEligible: true`; valores ausentes ou falsos excluem um provedor do benchmark de latência TCP.
- `config/applications.json` define os aplicativos instaláveis; cada entrada inclui os campos esperados pelos testes e pelo código da interface, como IDs do gerenciador de pacotes, categoria, conteúdo de exibição, descrição e link.
- `config/icons/<key>.png` guarda um ícone 48x48 por aplicativo, nomeado conforme sua chave em `config/applications.json` (sem o prefixo `WPFInstall`). O `Compile.ps1` embute a pasta como `$sync.configs.icons`, e a aba Instalar desenha os ícones sem qualquer acesso à rede (`Get-WinUtilAppIcon`); um aplicativo sem arquivo de ícone recorre à busca de favicon online. Adicione ou substitua um ícone com `tools/New-WinUtilIcon.ps1`; um teste Pester exige um ícone de no máximo 8 KB para cada aplicativo.
- `config/tweaks.json` define os ajustes do Windows; alterações de registro e de serviço incluem os valores originais ou os estados originais quando aplicável, para que os fluxos de desfazer possam restaurar o sistema do usuário.
- Arquivos de predefinição e de navegação referenciam chaves de configuração válidas. Renomear uma chave de configuração exige atualizar todas as predefinições, referências de interface, documentação e caminhos de código em conjunto.
- Adicionar ou renomear uma predefinição, adicionar um prefixo de chave de seleção ou adicionar um novo tipo de campo de alteração em ajustes também exige atualizar as páginas Tools da documentação (veja Site De Documentação).

## Requisitos De Segurança

- Operações de registro, serviço, gerenciador de pacotes, Windows Update, remoção de AppX e ISO afetam o sistema hospedeiro e são tratadas como de alto risco.
- Alterações de ajustes incluem metadados de desfazer quando o esquema permite, para que as mudanças permaneçam reversíveis.
- Fluxos de ISO nunca modificam o arquivo ISO original do usuário; eles trabalham sobre conteúdo copiado/montado.

## Site De Documentação (Astro)

- `docs/` é um site Astro + Starlight, independente do build do `Compile.ps1` (com seu próprio `package.json`/`node_modules`, publicado pelo workflow `docs.yaml` do GitHub Actions no GitHub Pages).
- As páginas ficam em `docs/src/content/docs/` (`.mdx`), organizadas em `guides/`, `code-reference/`, além das páginas de nível superior como `faq.mdx`, `knownissues.mdx`, `contributing.mdx`, `index.mdx`.
- `docs/src/content/docs/code-reference/tweaks/` e `.../features/` são gerados automaticamente por `tools/devdocs-generator.ps1` a partir de `config/tweaks.json`/`config/feature.json` e dos arquivos de função PowerShell relevantes. As demais páginas em `code-reference/` (por exemplo, `architecture.mdx`) são escritas à mão e não são tocadas pelo gerador.
- As entradas da barra lateral em `docs/astro.config.mjs` devem corresponder aos slugs reais das páginas em `docs/src/content/docs/`.
- A interface do site é conectada ao Starlight por meio de substituições de componentes em `docs/src/components/overrides/` (Header, Sidebar, MobileMenuToggle, TableOfContents, MobileTableOfContents, PageTitle, Pagination, ThemeSelect), registradas em `docs/astro.config.mjs`. As partes estáticas são componentes Astro; as partes interativas (busca, menus, sumário, alternador de tema) são ilhas React em `docs/src/components/docs/`. O Starlight continua responsável pelo roteamento, pela renderização de Markdown, pelo índice de busca Pagefind e pelas páginas de referência geradas. A página inicial (`index.mdx`) acrescenta componentes React Bits (`docs/src/components/react-bits/`, MIT + Commons Clause; veja o `LICENSE.md` deles) e movimento com GSAP + Lenis (`docs/src/scripts/landing-motion.js`, com componentes exclusivos da landing em `docs/src/components/landing/`). Esse movimento é totalmente ignorado para visitantes que preferem movimento reduzido.
- As páginas Tools, o Config Builder (`config-builder.mdx`, `docs/src/components/config-builder/`) e o Tweak Explorer (`tweak-explorer.mdx`, `docs/src/components/tweak-explorer/`) buscam `config/*.json` no navegador a partir da tag de release estável mais recente, por meio de `docs/src/lib/winutil-release.js`, em vez de empacotar a cópia do repositório, porque `-Config` executa a release estável e rejeita toda a importação em qualquer chave que não conheça.
  - Aplicativos, ajustes, interruptores, recursos, pacotes AppX e categorias novos ou removidos aparecem na próxima sessão do navegador após uma release ser marcada como Latest, sem reconstruir a documentação. Pré-releases não são consideradas. O Tweak Explorer só mostra um link de referência quando a configuração da release estável mais recente contém esse link, e a página dele existe depois que o PR de atualização da documentação da pré-release é mesclado e a documentação é republicada.
  - Três coisas estão codificadas de forma fixa e precisam ser atualizadas à mão quando o WinUtil as alterar: os nomes das predefinições (`Standard`, `Minimal`, `Advanced`, `AppxDefault`) em `ConfigBuilder.jsx` e `TweakExplorer.jsx`; os prefixos de chave importáveis (`WPFInstall`, `WPFTweaks`, `WPFToggle`, `WPFFeature`, `WPFAppx`) em `ConfigBuilder.jsx`, que espelham `Update-WinUtilSelections`; e os campos de alteração de ajuste (`registry`, `service`, `InvokeScript`, `UndoScript`, `appx` e os mapeamentos `Values` de registro para entradas `Combobox`) lidos por `TweakExplorer.jsx`, que espelham `Invoke-WinUtilTweaks` e `Set-WinUtilRegistryComboState`.
  - Links de compartilhamento do Config Builder, incluindo a passagem de bastão do Tweak Explorer, colocam as chaves selecionadas no hash da URL como uma lista separada por vírgulas, criada e lida por `docs/src/lib/config-link.js`. Os links são publicados publicamente, então o builder precisa continuar lendo esse formato.
- `docs/public/` é código-fonte versionado de ativos estáticos (favicons etc.), não saída gerada. Caminhos gerados/ignorados estão listados em `docs/.gitignore` (`dist/`, `.astro/`, `node_modules/`, arquivos de ambiente locais).
- `docs/src/assets/branding/title-screen.png` é uma imagem gerada e versionada, usada pelo README do repositório e pela página inicial da documentação. Suas capturas brutas em Claro e Escuro são temporárias.
- `docs/Dockerfile` e `docs/docker-compose.yml` (serviço `winutil-astro`) colocam em contêiner as ferramentas npm do site, incluindo o Playwright e seus navegadores (versão fixada em `docs/package.json`); veja Instalações De Dependências, Builds E Servidores De Desenvolvimento no AGENTS.md para saber por que e como os agentes devem usá-los em vez de rodar npm no host.

## Testes E CI

- `.\Compile.ps1` verifica se o compilador consegue gerar `winutil.ps1`.
- `.\Compile.ps1 -Run` compila e abre o utilitário gerado para verificação manual da interface.
- O Pester 5.8.0 executa a suíte em `pester/*.Tests.ps1`. O GitHub Actions (`unittests.yaml`) instala o Pester 5.8.0 do zero e roda com `-CI`, o que produz `testResults.xml` e encerra com código diferente de zero em caso de falha.
- O GitHub Actions também executa o PowerShell Script Analyzer com `lint/PSScriptAnalyser.ps1` a cada push.
- O `winutil.ps1` gerado pode aparecer localmente após a compilação. Ele continua sendo saída de build ignorada (veja o `.gitignore` da raiz) e não deve ser commitado.
- O workflow `title-screen`, acionado manualmente, compila o WinUtil a partir de `main` e abre um pull request somente com imagem quando a composição gerada muda. Esses pull requests exigem revisão manual. Execuções que falham retêm diagnósticos por 14 dias.

## Artefato De Release

O GitHub Actions é responsável por produzir o `winutil.ps1` de release a partir dos códigos-fonte do repositório. Uma release só é considerada válida se o script gerado veio do processo de compilação, e não de edições manuais diretas no `winutil.ps1`.
