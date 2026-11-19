# AGENTS.md

Instruções operacionais de uso direto para agentes de código. Leia este arquivo antes de cada tarefa.

**Só código que funciona. Termine o trabalho. Plausibilidade não é correção.**

O `SPEC.md` na raiz do repositório é o contrato do projeto — leia-o para saber o que é o WinUtil e como ele é arquitetado. Este arquivo cobre como trabalhar nele.

## 0. Inegociáveis

Estas regras têm prioridade sobre todo o resto deste arquivo quando houver conflito:

1. **Não edite `winutil.ps1` diretamente.** Ele é saída de build gerada (veja Modelo De Build no SPEC.md). Altere os arquivos-fonte e compile.
2. **Não commite `winutil.ps1`.** Ele é ignorado localmente e gerado pelo GitHub Actions para as releases.
3. **Nunca toque em `docs/src/content/docs/code-reference/tweaks/` nem em `docs/src/content/docs/code-reference/features/`.** Ambos são gerados automaticamente (veja Site De Documentação no SPEC.md). Edite o JSON de origem (`config/tweaks.json`, `config/feature.json`) ou o arquivo de função PowerShell relevante. Outras páginas escritas à mão em `code-reference/` (por exemplo, `architecture.mdx`) não são tocadas pelo gerador e podem ser editadas diretamente.
4. **Nunca invente.** Não invente caminhos de arquivo, nomes de função, saída de comando, resultados de teste, hashes de commit ou comportamento de API. Leia o arquivo ou rode o comando.
5. **Discorde quando a premissa estiver errada.** Diga o que está errado antes de agir com base nela.
6. **Pare quando houver ambiguidade real.** Se duas interpretações produzirem diffs materialmente diferentes, pergunte antes de editar.
7. **Mexa apenas no que a tarefa exige.** Nada de refatorações de passagem, varreduras de formatação ou limpeza não relacionada.
8. **Verifique antes de dizer que terminou.** Um diff de aparência plausível não é prova.

## 1. Comandos Principais

- Compilar:
  ```powershell
  .\Compile.ps1
  ```
- Compilar e abrir a interface:
  ```powershell
  .\Compile.ps1 -Run
  ```
- Instalar a versão suportada do Pester (uma vez). O `-SkipPublisherCheck` é necessário porque o Windows traz um Pester 3.4.0 de fábrica que é assinado por catálogo, e o Pester 5.8.0 da PowerShell Gallery é assinado com Authenticode — o `Install-Module` recusa a atualização sem isso. Isso não dispensa a verificação de integridade do download (continua HTTPS + verificação de hash do pacote NuGet); o `-Repository PSGallery` fixa explicitamente a origem confiável em vez de depender de quaisquer repositórios que estejam registrados:
  ```powershell
  Install-Module -Name Pester -RequiredVersion 5.8.0 -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck
  ```
- Rodar os testes:
  ```powershell
  Import-Module Pester -RequiredVersion 5.8.0 -Force
  Invoke-Pester -Path 'pester/*.Tests.ps1' -Output Detailed -CI
  ```
- Rodar o Script Analyzer com as configurações do projeto quando disponíveis. Se existir um `winutil.ps1` compilado localmente, apague-o antes — `lint/PSScriptAnalyser.ps1` só exclui regras, não arquivos, então `-Recurse` também analisaria o script gerado e produziria ruído contra números de linha que não mapeiam para nenhum arquivo-fonte:
  ```powershell
  Invoke-ScriptAnalyzer -Path . -Settings .\lint\PSScriptAnalyser.ps1 -Recurse
  ```
- Servidor de desenvolvimento do site de documentação (rode a partir de `docs/`; veja a Seção 2 para saber por que isso passa pelo Docker):
  ```powershell
  docker compose up winutil-astro
  ```
- Build de produção do site de documentação (rode a partir de `docs/`):
  ```powershell
  docker compose run --rm winutil-astro npm run build
  ```

Prefira a verificação mais estreita que seja útil enquanto itera. Use a verificação relevante completa antes de terminar.

## 2. Instalações De Dependências, Builds E Servidores De Desenvolvimento

Diante da onda atual de vermes de cadeia de suprimentos em npm/pnpm/yarn (scripts maliciosos de postinstall/preinstall, pacotes que roubam credenciais): **nunca rode npm/pnpm/yarn/npx diretamente no host, ponto final.** O site de documentação (`docs/`) é o único projeto baseado em npm neste repositório; sempre rode as ferramentas dele dentro do Docker, via `docs/Dockerfile` e `docs/docker-compose.yml` (serviço `winutil-astro`).

- Nunca rode `npm install`, `npm run <script>`, `npx <pkg>`, `pnpm` ou `yarn` diretamente no shell do host em `docs/`. Use `docker compose run --rm winutil-astro <command>` / `docker compose up winutil-astro` no lugar (veja a Seção 1 para os comandos exatos).
- Se uma tarefa precisar de uma nova dependência de documentação, adicione-a você mesmo em `docs/package.json`, depois reconstrua a imagem e remova o volume `node_modules` para que ele seja repovoado a partir da nova imagem (rode a partir de `docs/`): `docker compose build winutil-astro` e depois `docker compose down -v`. O Docker só semeia um volume nomeado a partir da imagem na primeira vez que ele é criado, então uma reconstrução simples deixa silenciosamente o `node_modules` antigo no lugar. Não instale pacotes no host, nem temporariamente, "só para checar uma coisa".
- Rode as verificações de navegador do Playwright também dentro do contêiner (`docker compose run --rm winutil-astro npx --no-install playwright ...`). A imagem instala navegadores para a versão de `@playwright/test` fixada em `docs/package.json`; suba essa versão fixada em vez de deixar o `npx` baixar um Playwright diferente.
- Se o Docker não estiver disponível no host, proponha o comando de instalação para o sistema operacional atual e espere a confirmação antes de rodá-lo — não recorra a rodar npm no host no lugar disso. Se o daemon apenas não estiver rodando (Docker instalado mas não iniciado), avise o usuário em vez de tentar iniciá-lo você mesmo.
- Trate qualquer script de ciclo de vida `postinstall`/`preinstall` em uma nova dependência como algo que merece ser sinalizado ao usuário antes da instalação — resuma o que ele faz.
- Não coloque segredos reais em lugar nenhum dentro de `docs/`. O `docs/.dockerignore` só reduz o que o `docker build` copia para a imagem — ele não afeta o bind mount do `docker compose`, que expõe todo o diretório `docs/` (incluindo qualquer arquivo `.env`) dentro do contêiner em todo comando de dev/build/preview (veja o próximo item). Não existe meio-termo de "deixar de fora a menos que montado" aqui.
- O contêiner monta `docs/` como volume, então edições de arquivo no host se refletem imediatamente dentro do contêiner — nenhuma reconstrução é necessária para mudanças normais de código, só quando `docs/package.json`/`docs/package-lock.json` mudam (veja os passos de reconstruir e remover o volume acima).
- Esta exigência de Docker é específica de `docs/`. As ferramentas PowerShell rodam diretamente no host conforme a Seção 1. O projeto Python em `tools/title-screen/` roda com uv conforme documentado no README dele.

## 3. Fonte Da Verdade

Para mudanças que afetam o script compilado do WinUtil, faça-as apenas nos arquivos-fonte descritos em Estrutura Do Repositório no SPEC.md — nunca no próprio `winutil.ps1`. Se mudanças de comportamento exigirem que o script compilado mude, atualize os arquivos-fonte e rode `.\Compile.ps1` apenas para verificar a geração.

Esse escopo se aplica somente ao comportamento do script compilado. Metadados do repositório — `AGENTS.md`, `SPEC.md`, `CLAUDE.md`/`GEMINI.md`/`.github/copilot-instructions.md`, `.github/workflows/` e o `.gitignore` da raiz — são editados diretamente quando uma tarefa exigir, conforme as outras seções deste arquivo.

## 4. Antes De Editar

- Declare o plano em uma ou duas frases antes de editar. Para trabalho não trivial, inclua a verificação que pretende rodar.
- Leia os arquivos que vai mexer e os arquivos que os chamam.
- Siga os padrões existentes mesmo quando um design novo do zero fosse mais limpo.
- Exponha premissas quando elas afetarem comportamento, compatibilidade ou dados do usuário.
- Se duas abordagens tiverem trocas relevantes, nomeie-as antes de escolher. Tarefas triviais podem seguir direto.

## 5. Diretrizes De Código

- Prefira o mínimo de código que resolve o problema declarado.
- Mantenha funções PowerShell em um arquivo de função quando for prático, com o nome do arquivo correspondendo ao nome da função principal.
- Use nomes verb-noun aprovados do PowerShell e siga as convenções de nomenclatura `WPF` / `WinUtil` existentes; mantenha os nomes dos manipuladores de evento de interface alinhados com os nomes dos elementos XAML, conforme Contrato De Interface E Eventos no SPEC.md.
- Use `$sync` para estado compartilhado e referências de interface, de forma consistente com Modelo De Execução no SPEC.md.
- Atualize controles WPF pelo dispatcher da interface quando estiver rodando trabalho em um runspace de segundo plano.
- Mantenha recursos orientados por configuração em JSON quando eles couberem no esquema existente, em vez de codificar listas fixas em PowerShell; siga Contrato De Configuração no SPEC.md para campos obrigatórios e regras de renomeação de chaves.
- Preserve dados de desfazer/estado original dos ajustes, para que os usuários possam reverter mudanças.
- Não adicione abstrações, configurabilidade, hooks ou "extensibilidade futura" a menos que a tarefa precise disso agora.
- Limpe órfãos criados pelas suas próprias mudanças, como variáveis ou funções que ficaram obsoletas com a edição.
- Evite edições amplas apenas de formatação, especialmente em arquivos JSON de configuração, XAML, documentação e saída gerada.

## 6. Regras De Execução E Segurança

- O WinUtil faz mudanças em nível de sistema no Windows; trate alterações de registro, serviços, remoção de AppX, gerenciador de pacotes, Windows Update, ISO e instalação autônoma como de alto risco (veja Requisitos De Segurança no SPEC.md).
- Prefira as funções auxiliares existentes para WinGet, Chocolatey, registro, serviços, progresso e atualizações de interface.
- Mantenha os ajustes reversíveis onde o esquema permite, incluindo os valores originais ou os estados originais.
- Nunca modifique o ISO original do usuário no lugar; siga os padrões existentes de copiar/montar/exportar.
- Evite armazenar credenciais, segredos ou caminhos específicos da máquina em arquivos do repositório.
- Preserve os padrões de log e de retorno ao usuário para operações longas ou destrutivas.

## 7. Mudanças Cirúrgicas

- Não melhore código, comentários, formatação, imports ou documentação adjacentes a menos que seja necessário.
- Não refatore código que funciona só porque você já está no arquivo.
- Não apague código morto preexistente a menos que seja pedido; mencione no resumo se for relevante.
- Mantenha os diffs revisáveis. Cada linha alterada deve remontar ao pedido do usuário.
- Se uma mudança começar a se espalhar por áreas não relacionadas, pare e reavalie o plano.

## 8. Verificação

Defina sucesso em termos que possam ser checados, e então cheque.

- Para mudanças de compilação/build, rode `.\Compile.ps1`.
- Para mudanças de comportamento da interface, rode `.\Compile.ps1 -Run` quando for prático e verifique manualmente o caminho afetado.
- Para mudanças de configuração, rode a checagem de compilação e os testes Pester relevantes.
- Para mudanças de função, rode os testes Pester relevantes ou adicione/atualize testes focados quando for prático.
- Para mudanças apenas de documentação, revise os arquivos alterados e pule os testes de execução, a menos que a geração da documentação seja afetada.
- Leia a saída dos comandos. Não reporte testes como passando a menos que eles realmente tenham passado.
- Se a verificação falhar, corrija a causa em vez de enfraquecer o teste.

Se uma checagem não puder ser rodada, diga exatamente por quê e qual risco residual permanece. Veja Testes E CI no SPEC.md para saber o que o GitHub Actions roda a cada push.

## 9. Arquivos Gerados E Higiene De Git

- Trate mudanças locais no `winutil.ps1` como saída de compilação descartável.
- Nunca faça stage nem commite `winutil.ps1`, `binary/` ou qualquer outra coisa ignorada pelo `.gitignore` da raiz ou pelo `docs/.gitignore` — leia esses arquivos em vez de presumir. `docs/public/` é código-fonte versionado de ativos estáticos, não saída gerada.
- `docs/src/assets/branding/title-screen.png` é um ativo gerado e versionado. Não o edite manualmente. Atualize `tools/title-screen/` ou rode o workflow title-screen.
- Não remova regras do `.gitignore` que mantêm artefatos gerados fora do Git.
- Antes de terminar, verifique `git status --short` e separe suas mudanças de mudanças preexistentes do usuário.
- Não reverta mudanças do usuário a menos que seja explicitamente pedido.
- Mensagens de commit, quando solicitadas, devem ser descritivas: assunto curto com menos de 72 caracteres, corpo explicando o porquê quando necessário.
- Ao commitar, divida as mudanças em commits pequenos e lógicos em vez de um commit grande, para que o diff de cada commit seja revisável como um único grupo de mudanças relacionadas.

## 10. Expectativas De Documentação

- Atualize `docs/src/content/docs/guides/` quando o comportamento visível ao usuário mudar.
- Atualize `docs/src/content/docs/code-reference/architecture.mdx` e outras documentações de desenvolvedor escritas à mão quando arquitetura, fluxo de build, esquema de configuração ou fluxo de contribuição mudarem — mas nunca edite à mão as subpastas `code-reference/tweaks/` ou `code-reference/features/` geradas automaticamente (veja Inegociáveis).
- Mantenha as entradas da barra lateral em `docs/astro.config.mjs` sincronizadas com os slugs das páginas (veja Site De Documentação no SPEC.md).
- Quando uma mudança adicionar ou renomear uma predefinição, adicionar um prefixo de chave de seleção ou der aos ajustes um novo tipo de campo de alteração, atualize o Config Builder e o Tweak Explorer na mesma mudança (Site De Documentação no SPEC.md lista os arquivos exatos). Quando você adicionar uma nova página de ferramenta na documentação, ou qualquer outra coisa que precise ser mantida em sincronia à mão, registre isso em Site De Documentação no SPEC.md e em `docs/README.md`.
- Mantenha as mudanças no README breves e de alto nível.
- Coloque a documentação detalhada de usuário e de desenvolvedor em `docs/`.
- Mantenha o SPEC.md alinhado com mudanças de projeto/arquitetura, e este arquivo alinhado com mudanças de processo.

## 11. Estilo De Comunicação

- Seja direto e conciso. Comece pela resposta ou pela ação.
- Sem bajulação, enrolação, encerramentos cerimoniais ou certeza falsa.
- Use marcadores apenas quando eles melhorarem a leitura rápida.
- Relate o que mudou, como foi verificado e o que não foi feito.
- Se o usuário pedir uma revisão, comece pelos achados e pelas referências de arquivo/linha.

## 12. Quando Perguntar

Pergunte antes de prosseguir quando:

- O pedido tiver duas interpretações plausíveis e a escolha mudar materialmente o comportamento ou os arquivos tocados.
- A mudança afetar a geração de release, artefatos gerados, migrações ou comportamento de alto risco no Windows de um jeito que o usuário não especificou.
- Você precisar de credenciais, segredos, recursos de produção ou acesso que não tem.
- O objetivo declarado pelo usuário conflitar com o pedido literal.

Prossiga sem perguntar quando:

- A tarefa for trivial e reversível.
- A ambiguidade puder ser resolvida lendo o código ou rodando um comando local.
- O usuário já tiver respondido à pergunta nesta sessão.

## 13. Aprendizados Do Projeto

Quando o usuário corrigir a abordagem de um agente, adicione ou aperte uma regra concreta aqui antes de encerrar a sessão. Mantenha esta seção curta e poda regras que não importam mais.

- Mantenha o `winutil.ps1` apenas como gerado: altere os arquivos-fonte, compile para verificar e nunca faça stage do script gerado.
- Mantenha o log de execução do WinUtil no arquivo de sessão existente com data e hora `%LocalAppData%\winutil\logs\winutil_*.log`; não crie um `winutil.log` separado na raiz.
- Importe o Pester 5.8.0 antes de rodar os testes, para que `Invoke-Pester -Output Detailed -CI` não resolva para o Pester 3.4.0 de fábrica do Windows.
- Mantenha simples os lançamentos de processo de instalação/desinstalação de pacotes, a menos que seja pedido explicitamente; não adicione um auxiliar separado de log de processo stdout/stderr para winget ou Chocolatey.
- Não use `Start-Transcript` para o log de sessão; ele só registra o runspace que o iniciou, então a thread de interface e os jobs nunca chegavam ao arquivo. Registre por `Write-WinUtilLog` e use `Write-WinUtilHost` em vez de `Write-Host` para saída apenas de console, como banners e progresso.
- Mantenha auxiliares de interface como `Invoke-WPFUIThread` e `Step-WinUtilJob` seguros para chamar sem janela; os caminhos `-Preset` e `-Config` rodam os fluxos antes de o formulário ser criado e antes de o PresentationCore ser carregado. Pergunte a `Test-WinUtilUIAlive` em vez de escrever à mão a checagem de `$sync.Form` / dispatcher / `HasShutdownStarted`.
- Coloque operações longas na camada de jobs com `Start-WinUtilJob` e reporte a partir delas com `Step-WinUtilJob`; o corpo de um job não deve definir o flag de ocupado, imprimir seu próprio banner nem carregar seu próprio try/catch/finally em volta da interface. `Invoke-WPFRunspace` diretamente é para trabalho disparar-e-esquecer que não é um job.
- Escoe o trabalho de interface pelo qual ninguém está esperando através de `Start-WinUtilBackgroundQueue`; não improvise outra bomba de desenfileirar-e-repostar.
- Valores de que um scriptblock postado precisa devem viajar como argumento do dispatcher ou por `-Parameters`, nunca capturados do chamador: um bloco comum os resolve quando o dispatcher chega nele, e `GetNewClosure` amarra a busca de comando a um escopo copiado. Pelo mesmo motivo, prefira um `[action]` compilado a `Invoke-WPFUIThread -Async` em caminhos quentes de repostagem, que faz marshal do corpo como texto e o recompila a cada post.
- Andaime de diagnóstico não vai para produção. Meça com ele, depois apague.
- Faça cada arquivo Pester carregar os assemblies e dar dot-source nas funções de que precisa; vários só passavam porque um arquivo anterior em ordem alfabética acabou carregando-as.
- Registre em log os nomes de pacote e os IDs do gerenciador de pacotes de instalação/desinstalação antes de enfileirar trabalho de runspace em segundo plano; não dependa da saída do host do runspace para a identidade do pacote.
- Para o Criador do Win11, comece cada nova modificação de ISO em um diretório temporário novo `WinUtil_Win11ISO_*`; a detecção de trabalho existente serve apenas para retomar/exportar mídia já modificada.
- Para a injeção de drivers do Criador do Win11, injete controladores de armazenamento (`SCSIAdapter` / `HDC`) no índice 2 do `boot.wim` com DISM, não em `$WinpeDriver$`. Mantenha o `install.wim` com seu próprio laço de tentativas `/Add-Driver` por pacote. Para cada imagem, adicione cada pasta de pacote raiz com seu próprio `/Add-Driver /Recurse`, para que um único driver ruim não derrube o resto, e pule qualquer pasta cujo ancestral já esteja no conjunto, já que o `/Recurse` desse ancestral a cobre. Avise por falha e faça commit apenas quando ao menos um pacote tiver sido adicionado; quando nenhum tiver sido, avise e descarte em vez de lançar exceção, para que a execução ainda produza um ISO. O descarte no bloco de limpeza carrega tanto montagens órfãs quanto esse caso intencional de zero adições; mantenha-o. Não exporte edições nem rode limpeza de WIM não relacionada, e rejeite metadados danificados antes da exportação do ISO. Use `-LiteralPath` para caminhos de exportação de drivers, já que `%TEMP%` pode conter caracteres curinga.
- Para limpeza do Script Analyzer, corrija primeiro os avisos acionáveis na origem e não suprima globalmente avisos de convenção aceitos, como nomes no plural, `ShouldProcess` em auxiliares de interface, `$global:sync` ou falsos positivos entre arquivos em tempo de compilação.
- Para o reset de DHCP do DNS, mantenha o reset via cmdlet e defina explicitamente a origem de DNS de IPv4 e IPv6 para DHCP.
- Diffs públicos de pull request podem ser enviados a serviços de revisão externos configurados sem uma aprovação de privacidade separada; não bloqueie o ciclo de revisão por autorização de upload neste repositório público.
- Busque e inspecione código frontend de terceiros (fontes do React Bits, metadados do registro npm, tarballs de pacotes) dentro do contêiner `winutil-astro`, não com `curl`/`python` do host; só os arquivos revisados entram no repositório.
- Mantenha o carregamento de favicons da aba Instalar sobreposto à renderização das entradas de aplicativos; não substitua o carregamento nativo do WPF por uma segunda fase adiada a menos que o tempo de conclusão visível comprovadamente não seja mais lento que o de `main`.
