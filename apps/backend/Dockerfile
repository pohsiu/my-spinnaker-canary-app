FROM node:20-alpine AS frontend-build
WORKDIR /repo
COPY package.json package-lock.json ./
COPY apps/frontend/package.json apps/frontend/package.json
COPY apps/backend/package.json apps/backend/package.json
RUN npm ci --workspace=frontend
COPY apps/frontend apps/frontend
RUN npm run build --workspace=frontend

FROM node:20-alpine
WORKDIR /app
COPY apps/backend/package.json ./
RUN npm install --omit=dev
COPY apps/backend/server.js ./
COPY --from=frontend-build /repo/apps/frontend/dist /frontend/dist

EXPOSE 3000
CMD ["node", "server.js"]
