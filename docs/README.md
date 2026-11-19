# Documentação do WinUtil

[![Feito com Starlight](https://astro.badg.es/v2/built-with-starlight/tiny.svg)](https://starlight.astro.build)

Site de documentação do [WinUtil](https://github.com/RamonMods/WinUtil), feito com [Astro](https://astro.build), [Starlight](https://starlight.astro.build) e [React](https://react.dev).

O Starlight cuida das rotas, da renderização do Markdown e do índice de busca. A interface do site entra pelos overrides de componente do Starlight: as partes estáticas (barra lateral, títulos, paginação) são componentes Astro, e as interativas (busca, menus, sumário, troca de tema) são ilhas React.

## 🚀 Estrutura do projeto

```
.
├── public/                  # Arquivos servidos como estão (favicon, robots.txt, preview social)
├── src/
│   ├── assets/              # Imagens das páginas (otimizadas no build); icons/ guarda os ícones da interface
│   ├── components/
│   │   ├── config-builder/  # Componente e estilos da página Config Builder
│   │   ├── docs/            # Interface dos docs: ilhas React (busca, menus, sumário, tema) e a lista da barra lateral
│   │   ├── landing/         # Componentes só da landing page (estatísticas, cards, wrapper de animação)
│   │   ├── overrides/       # Overrides do Starlight (wrappers .astro finos, registrados no astro.config.mjs)
│   │   ├── react-bits/      # Componentes do React Bits copiados para cá (veja react-bits/LICENSE.md)
│   │   ├── tweak-explorer/  # Componente e estilos da página Tweak Explorer
│   │   └── YouTubeEmbed.astro
│   ├── content/
│   │   └── docs/            # Páginas (.md/.mdx); code-reference/tweaks e /features são gerados
│   ├── hooks/               # Hooks React
│   ├── lib/                 # Código compartilhado (links do site, leitor de release, links de configuração)
│   ├── scripts/             # Scripts do cliente (animação GSAP + Lenis da landing)
│   ├── styles/              # CSS global: tema, fontes, interface dos docs
│   └── content.config.ts
├── astro.config.mjs
├── docker-compose.yml
├── Dockerfile
├── package.json
└── tsconfig.json
```

Cada arquivo `.md` ou `.mdx` em `src/content/docs/` vira uma rota conforme o caminho do arquivo. Não edite à mão `src/content/docs/code-reference/tweaks/` nem `.../features/`: eles são gerados a partir de `config/tweaks.json` e `config/feature.json` pelo `tools/devdocs-generator.ps1`.

Imagens podem ficar em `src/assets/` e ser embutidas no Markdown com link relativo.

Arquivos estáticos, como favicons, ficam em `public/`.

## 🧰 Páginas de ferramentas

O Config Builder (`/config-builder/`) e o Tweak Explorer (`/tweak-explorer/`) carregam os `config/*.json` no navegador a partir da última versão estável do WinUtil, por meio de `src/lib/winutil-release.js`. Eles não usam a cópia deste repositório, porque o `-Config` roda a versão estável e rejeita qualquer chave que não conheça.

Apps, ajustes, toggles, recursos, pacotes AppX e categorias novos aparecem na próxima sessão do navegador depois que uma versão é marcada como Latest. Não precisa rebuildar os docs, e pré-versões são ignoradas. Algumas coisas são fixas no código e precisam ser atualizadas aqui quando o WinUtil mudar:

- Nomes de predefinição (`Standard`, `Minimal`, `Advanced`, `AppxDefault`), em `ConfigBuilder.jsx` e `TweakExplorer.jsx`.
- Os prefixos de chave que o WinUtil importa (`WPFInstall`, `WPFTweaks`, `WPFToggle`, `WPFFeature`, `WPFAppx`), em `ConfigBuilder.jsx`. Eles espelham o `Update-WinUtilSelections`.
- Os campos de ajuste que o explorer mostra (`registry`, `service`, `InvokeScript`, `UndoScript`, `appx` e os mapeamentos de `Values` de registro para entradas `Combobox`), em `TweakExplorer.jsx`. Eles espelham o `Invoke-WinUtilTweaks` e o `Set-WinUtilRegistryComboState`.

Os links do Config Builder carregam as chaves selecionadas no hash da URL, por exemplo `/config-builder/#WPFInstall7zip,WPFTweaksTelemetry`. O `src/lib/config-link.js` monta e lê esses links nas duas páginas. As pessoas compartilham esses links, então mantenha a leitura do formato atual se um dia mudar.

Se você adicionar outra página de ferramenta, ou qualquer coisa que precise ser mantida em sincronia à mão, liste aqui e na seção Docs Site do SPEC.md.

## 🧞 Comandos

Todos os comandos rodam num container Docker — não precisa instalar Node nem dependências npm na sua máquina. Isso é de propósito: npm/pnpm/yarn sofrem ataques de cadeia de suprimentos com frequência (scripts `postinstall`/`preinstall` maliciosos, pacotes que roubam credenciais), então `npm install` e similares nunca rodam direto na máquina de quem contribui. O container tem acesso de leitura e escrita a esta pasta `docs/` (ela é montada para o live reload), então o estrago de um pacote comprometido fica na pasta do projeto e no container — não chega ao resto do host (chaves SSH, outros repositórios, credenciais na nuvem). Por isso, não guarde segredo real em `docs/`.

É preciso ter [Docker](https://www.docker.com/) (com Compose) — instale o Docker Desktop (ou Docker Engine + plugin `docker compose` no Linux) e deixe o daemon rodando antes dos comandos abaixo.

Todos os comandos rodam a partir da pasta `docs/`, num terminal:

| Comando                                          | O que faz                                        |
| :------------------------------------------------ | :----------------------------------------------- |
| `docker compose build`                             | Monta a imagem de desenvolvimento (necessário após mudar o Dockerfile ou dependências) |
| `docker compose up winutil-astro`                                | Sobe o servidor local em `localhost:4321`      |
| `docker compose run --rm winutil-astro npm run build`   | Gera o site de produção em `./dist/`           |
| `docker compose run --rm --service-ports winutil-astro npm run preview -- --host 0.0.0.0` | Pré-visualiza o build localmente, antes de publicar |
| `docker compose run --rm winutil-astro npm run astro ...` | Roda comandos da CLI, como `astro add` e `astro check` |
| `docker compose run --rm winutil-astro npx --no-install playwright ...` | Roda o Playwright no Chromium, Firefox ou WebKit |
| `docker compose down`                              | Para e remove o container de desenvolvimento     |

Os arquivos ficam montados no container, então edições na máquina aparecem na hora no servidor — não precisa rebuildar para mudanças normais de conteúdo ou código. Depois de mudar `package.json`, `package-lock.json` ou o `Dockerfile`, rebuilda a imagem **e** apaga o volume `node_modules`, porque o Docker só popula um volume nomeado a partir da imagem na primeira criação — um rebuild simples mantém o `node_modules` antigo:

```sh
docker compose build
docker compose down -v
docker compose up winutil-astro
```

A imagem também instala os navegadores do Playwright na versão de `@playwright/test` fixada no `package.json`, então subir essa versão exige o mesmo rebuild para baixar os navegadores correspondentes.

O primeiro `docker compose up` (ou qualquer comando antes de existir imagem) monta a imagem e roda `npm ci` do zero, o que pode levar alguns minutos. Depois disso a imagem em cache é reaproveitada e sobe quase na hora.

## 👀 Quer saber mais?

Veja a [documentação do Starlight](https://starlight.astro.build/) (inclusive o [guia de overrides de componente](https://starlight.astro.build/guides/overriding-components/)), leia a [documentação do Astro](https://docs.astro.build) ou entre no [Discord do Astro](https://astro.build/chat).
