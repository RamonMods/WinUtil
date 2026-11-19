// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import react from '@astrojs/react';
import { siteLinks } from './src/lib/site-links.ts';

// https://astro.build/config
export default defineConfig({
	site: 'https://github.com/RamonMods/WinUtil/',
	integrations: [
		starlight({
			title: 'WinUtil — Utilitário para Windows',
			description: 'O utilitário do Ramon para Windows — instale aplicativos, aplique ajustes, rode correções e gerencie o Windows em um só lugar.',
			logo: {
				src: './src/assets/branding/navlogo.png',
				replacesTitle: true,
			},
			favicon: '/favicon.svg',
			head: [
				{ tag: 'meta', attrs: { property: 'og:image', content: 'https://github.com/RamonMods/WinUtil/social-preview.png' } },
				{ tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
				{ tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
				{ tag: 'meta', attrs: { name: 'twitter:image', content: 'https://github.com/RamonMods/WinUtil/social-preview.png' } },
			],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/RamonMods/WinUtil' },
				{ icon: 'discord', label: 'Discord', href: 'https://github.com/RamonMods/WinUtil' },
			],
			// Sobrescritas de tema globais (cores, fontes, estilos das seções da página inicial).
			customCss: ['./src/styles/theme.css'],
			// Sobrescritas de componentes, todas em src/components/overrides/.
			components: {
				ThemeProvider: './src/components/overrides/ThemeProvider.astro',
				Header: './src/components/overrides/Header.astro',
				Hero: './src/components/overrides/Hero.astro',
				Footer: './src/components/overrides/Footer.astro',
				Sidebar: './src/components/overrides/Sidebar.astro',
				MobileMenuToggle: './src/components/overrides/MobileMenuToggle.astro',
				TableOfContents: './src/components/overrides/TableOfContents.astro',
				MobileTableOfContents: './src/components/overrides/MobileTableOfContents.astro',
				PageTitle: './src/components/overrides/PageTitle.astro',
				Pagination: './src/components/overrides/Pagination.astro',
				ThemeSelect: './src/components/overrides/ThemeSelect.astro',
			},
			editLink: {
				baseUrl: 'https://github.com/RamonMods/WinUtil/edit/main/docs/',
			},
			// Grupos da barra lateral, de cima para baixo: Guia do Usuário, Referência de código, Ajuda, Ferramentas.
			sidebar: [
				{
					label: 'Guia do Usuário',
					items: [
						{ label: 'Visão geral', slug: 'guides' },
						{ label: 'Primeiros passos', slug: 'guides/getting-started' },
						{ label: 'Aplicativos', slug: 'guides/application' },
						{ label: 'Ajustes', slug: 'guides/tweaks' },
						{ label: 'Recursos', slug: 'guides/features' },
						{ label: 'Atualizações', slug: 'guides/updates' },
						{ label: 'Automação', slug: 'guides/automation' },
						{ label: 'Criador do Win11', slug: 'guides/win11creator' },
					],
				},
				{
					label: 'Referência de código',
					items: [
						{ label: 'Arquitetura e design', slug: 'code-reference/architecture' },
						{ label: 'Comandos de triagem de issues', slug: 'code-reference/issue-triage' },
						{ label: 'Referência de ajustes', items: [{ autogenerate: { directory: 'code-reference/tweaks' } }] },
						{ label: 'Referência de recursos', items: [{ autogenerate: { directory: 'code-reference/features' } }] },
					],
				},
				{
					label: 'Ajuda',
					items: [
						{ label: 'Perguntas frequentes', slug: 'faq' },
						{ label: 'Problemas conhecidos', slug: 'knownissues' },
						{ label: 'Como contribuir', slug: 'contributing' },
						{ label: siteLinks.forums.label, link: siteLinks.forums.href, attrs: { target: '_blank', rel: 'noreferrer' } },
					],
				},
				{
					label: 'Ferramentas',
					items: [
						{ label: 'Construtor de configuração', slug: 'config-builder' },
						{ label: 'Explorador de ajustes', slug: 'tweak-explorer' },
					],
				},
				{ label: siteLinks.store.label, link: siteLinks.store.href, attrs: { target: '_blank', rel: 'noreferrer' } },
			],
		}),
		// Componentes React para a interface dos docs e a página inicial.
		react(),
	],
});
