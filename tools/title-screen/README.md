# Tela de título do WinUtil

Esta ferramenta gera a composição Claro e Escuro usada como tela de título do
WinUtil no README do repositório e no site de documentação. Ela abre a aba
Ajustes, captura ambos os temas e os combina em um único PNG. As duas capturas
brutas são temporárias e são removidas quando o comando termina.

## Requisitos

- Windows com uma área de trabalho interativa
- [uv](https://docs.astral.sh/uv/)
- WinUtil compilado e em execução
- Um terminal do PowerShell elevado

Execute os comandos abaixo em `tools/title-screen`.

## Gerar e revisar uma imagem de teste

Inicie o WinUtil a partir da raiz do repositório:

```powershell
.\Compile.ps1 -Run
```

Com o WinUtil ainda aberto, retorne a este diretório em um terminal elevado e
gere uma imagem de teste:

```powershell
uv run --locked python automate_title_screen.py --output "$env:TEMP\winutil-title-screen.png"
```

Abra o PNG resultante e verifique se:

- a aba Ajustes está exibida,
- o tema Claro está no lado superior esquerdo da diagonal,
- o tema Escuro está no lado inferior direito, e
- nenhum plano de fundo da área de trabalho ou outras janelas estão visíveis.

A automação funciona tanto se o WinUtil iniciar no modo Claro quanto no modo
Escuro. Ela deixa a janela na aba Ajustes no modo Claro.

## Automação

A tela de título é atualizada por meio de um fluxo de trabalho (workflow) do
GitHub Actions acionado manualmente. Quando a imagem gerada muda, o fluxo abre
ou atualiza um pull request para revisão; ele não o mescla automaticamente.

Execuções com falha enviam o log de captura, a inspeção da Automação de Interface do Usuário (UI Automation) e a imagem disponível
como artefatos de diagnóstico por 14 dias.

## Testes

Os testes cobrem a detecção de tema e a geração da imagem composta sem abrir o
WinUtil:

```powershell
uv run --locked python -m unittest discover
```

## Solução de problemas

Se o WinUtil não for encontrado, verifique se a janela WPF compilada está aberta
e se o terminal está elevado. O script ignora deliberadamente editores,
terminais e janelas de navegador que apenas contêm "WinUtil" no título.

Se não for possível encontrar uma aba ou um controle de tema, capture a árvore
de Automação de Interface do Usuário com o WinUtil aberto:

```powershell
uv run --locked python inspect_winutil.py "$env:TEMP\winutil-inspect.txt"
```

O inspetor abre o menu de temas antes de registrar seus controles. Anexe o
arquivo de texto ao relatar uma falha. Ele contém metadados de janelas e
controles, não as capturas de tela geradas.
