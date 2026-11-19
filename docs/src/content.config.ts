import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({
		loader: docsLoader(),
		schema: docsSchema({
			extend: () =>
				z.object({
					// Pequena linha em maiúsculas acima do título do hero, ex.: "Utilitário de configuração do Windows de código aberto".
					heroEyebrow: z.string().optional(),
					// Linha discreta abaixo das ações do hero, ex.: "Auto-hospedado. Baseado em script. Sem instalador.".
					heroCaption: z.string().optional(),
					// Imagens de selos (shields.io etc.) exibidas em uma linha na parte inferior do hero.
					heroBadges: z
						.array(
							z.object({
								src: z.string(),
								alt: z.string(),
								href: z.string().optional(),
							})
						)
						.optional(),
				}),
		}),
	}),
};
