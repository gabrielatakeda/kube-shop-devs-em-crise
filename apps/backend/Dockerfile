FROM node:24.15.0-alpine3.23 AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/backend/package.json apps/backend/package.json
COPY apps/frontend/package.json apps/frontend/package.json
RUN npm ci --omit=dev --workspace apps/backend --ignore-scripts

FROM node:24.15.0-alpine3.23 AS runtime
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3000
# A API roda com "node" puro: npm, npx e yarn da imagem base não são usados em
# execução e traziam CVE crítica (tar 7.5.11, CVE-2026-59873). Removidos para
# reduzir a superfície de ataque; pacotes do Alpine atualizados.
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
           /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /app
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --from=dependencies --chown=node:node /app/apps/backend ./apps/backend
COPY --chown=node:node apps/backend/src ./apps/backend/src
COPY --chown=node:node scripts/smoke.mjs ./scripts/smoke.mjs
WORKDIR /app/apps/backend
USER node
EXPOSE 3000
CMD ["node", "src/server.js"]
