ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-bookworm-slim

RUN corepack enable

WORKDIR /app

# Mantém os navegadores do Playwright fora do diretório inicial do root para que o usuário node possa acessá-los.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Dependências primeiro para aproveitar o cache de camadas; os scripts de ciclo de vida permanecem ativos porque Astro/Vite precisam de alguns.
COPY package*.json ./
RUN npm ci

# Navegadores e suas bibliotecas do sistema para os testes do Playwright; precisa de root para o apt-get.
# --no-install faz a compilação falhar em vez de buscar um Playwright sem versão fixada se ele estiver ausente do package.json.
RUN npx --no-install playwright install --with-deps chromium firefox webkit \
    && rm -rf /var/lib/apt/lists/*

COPY . .

# Executa como um usuário não-root para defesa em profundidade.
RUN chown -R node:node /app "$PLAYWRIGHT_BROWSERS_PATH"
USER node

EXPOSE 4321
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
