---
title: "Gerador de Docs de Desenvolvimento"
description: "Como funciona o script devdocs-generator.ps1"
---

# Gerador de Docs de Desenvolvimento

O script `devdocs-generator.ps1` gera automaticamente arquivos markdown (`.mdx`) do Astro/Starlight para a documentação de desenvolvimento. Ele obtém o conteúdo diretamente dos arquivos de configuração JSON e dos arquivos de função do PowerShell, para que a documentação nunca fique desatualizada.

## Quando ele é executado?

- É executado automaticamente como parte do fluxo de trabalho (workflow) `pre-release.yaml` do GitHub Actions (acionado manualmente via `workflow_dispatch`), que regenera os arquivos `.mdx` e atualiza as propriedades `"link"` nos arquivos de configuração JSON
- Em seguida, `pre-release.yaml` abre um pull request `docs-update` com essas alterações; `auto-merge-docs.yaml` aprova e mescla automaticamente o pull request na branch `main`
- Essa mescla envia as alterações em `docs/**`, o que aciona `docs.yaml` — mas `docs.yaml` apenas compila e publica o site Astro, sem executar o gerador em si
- Também pode ser executado manualmente/localmente a partir de `tools/` (`./devdocs-generator.ps1`)

## O que ele faz?

### 1. Carrega os dados

- Lê `config/tweaks.json` e `config/feature.json`
- Lê todos os arquivos de função `.ps1` de `functions/public/` e `functions/private/`
- Analisa `Invoke-WPFButton.ps1` para montar um mapa de nomes de botão para nomes de função

### 2. Atualiza os links no JSON

- Adiciona ou atualiza uma propriedade `"link"` em cada entrada dos dois arquivos de configuração JSON
- Cada link aponta para a página de documentação dessa entrada no site Astro/Starlight
- Os links atualizados são automaticamente comitados de volta nos arquivos de configuração JSON como parte do fluxo de pré-lançamento (pre-release)

### 3. Limpa a documentação antiga

- Exclui todos os arquivos `.mdx` de `docs/src/content/docs/code-reference/tweaks/` e `docs/src/content/docs/code-reference/features/`
- Isso evita arquivos duplicados ou órfãos de execuções anteriores
- Ainda não existem páginas de entrada `index.mdx` por categoria; se uma for adicionada depois, a exclusão correspondente no script fica comentada, pronta para ser reativada

### 4. Gera a documentação dos ajustes

Para cada entrada em `tweaks.json` que pertence a uma categoria documentada:

- As entradas do tipo **Button** recebem o arquivo de função do PowerShell mapeado incorporado
- **Todos os outros tipos** recebem o trecho JSON bruto incorporado com os números de linha corretos do arquivo de origem
- As entradas com **alterações no registro** recebem uma seção de Alterações no Registro

### 5. Gera a documentação dos recursos

Para cada entrada em `feature.json` que pertence a uma categoria documentada:

- **Fixes e Legacy Windows Panels** recebem o arquivo de função do PowerShell mapeado incorporado
- **Features** recebem o trecho JSON bruto incorporado com os números de linha corretos

### 6. Formato de saída

- Cada arquivo `.mdx` recebe um frontmatter do Starlight com `title` e `description` (a descrição vem do campo `Description` da entrada, quando presente). Os valores são serializados como strings JSON entre aspas, que são escalares YAML válidos e preservam caminhos do Windows, aspas e quebras de linha.
- Um bloco `:::note` aponta de volta para o arquivo de origem (configuração JSON ou função do PowerShell) a partir do qual foi gerado
- Os blocos de código usam a sintaxe do Starlight/Expressive Code com um atributo `title` que nomeia o arquivo de origem
- Os arquivos são organizados em subdiretórios de categoria correspondentes ao campo `category` do JSON

## Categorias documentadas

O script gera documentação para entradas nestas categorias:

- Essential Tweaks
- z--Advanced-Tweaks---CAUTION
- Customize Preferences
- Performance Plans
- Features
- Fixes
- Legacy Windows Panels

## Estrutura de arquivos

```
docs/src/content/docs/code-reference/
  tweaks/
    Essential-Tweaks/
    z--Advanced-Tweaks---CAUTION/
    Customize-Preferences/
    Performance-Plans/
  features/
    Features/
    Fixes/
    Legacy-Windows-Panels/
```

A barra lateral do Starlight detecta esses arquivos automaticamente por meio das entradas `autogenerate` em `docs/astro.config.mjs` para os diretórios `code-reference/tweaks` e `code-reference/features`, portanto não é necessário editar a barra lateral quando novas entradas são adicionadas.

## Como os nomes de arquivo são derivados

O script remove prefixos comuns dos nomes das chaves JSON usando o padrão `WPF(WinUtil|Toggle|Features?|Tweaks?|Panel|Fix(es)?)?`. Por exemplo:

| Chave JSON          | Arquivo gerado |
| ------------------- | -------------- |
| `WPFTweaksHiber`    | `Hiber.mdx`     |
| `WPFTweaksDeBloat`  | `DeBloat.mdx`   |
| `WPFFeatureshyperv` | `hyperv.mdx`    |
| `WPFPanelDISM`      | `DISM.mdx`      |

## Pontos principais

- Os arquivos de configuração JSON são a única fonte da verdade
- Edições manuais nos arquivos `.mdx` gerados serão sobrescritas na próxima execução
- O script só mexe em `docs/src/content/docs/code-reference/tweaks/` e `.../features/` — `architecture.mdx` e qualquer outra página escrita à mão em `code-reference/` não são alteradas
  — se uma página de entrada `index.mdx` de categoria for adicionada dentro de `tweaks/` ou `features/`, descomente a exclusão na etapa de limpeza primeiro, ou ela será excluída na próxima execução
- Os diretórios de categoria são criados automaticamente caso não existam
- A propriedade `"link"` adicionada às entradas JSON é excluída dos blocos de código exibidos
- O fluxo `pre-release` gera tanto os arquivos `.mdx` quanto as propriedades `"link"` e os comita de volta no repositório por meio do PR `docs-update`
- O fluxo `docs` nunca executa o gerador — ele apenas compila e publica o site Astro já comitado
