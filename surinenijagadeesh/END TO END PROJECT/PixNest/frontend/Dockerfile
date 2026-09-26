# Multi-stage build for the pixnest frontend.

# Stage 1: build the static assets.
FROM node:22-slim AS build
WORKDIR /app

# Install dependencies first so this layer is cached when only source changes.
COPY package.json package-lock.json ./
RUN npm ci

# Build the production bundle.
COPY . .
RUN npm run build

# Stage 2: serve the static build with unprivileged nginx on port 8080.
FROM nginxinc/nginx-unprivileged:1.31.5-alpine AS runtime

# Base images lag behind the distro's security updates, so patch the OS packages. The image
# runs as uid 101; apk needs root, so switch back afterwards.
USER root
RUN apk --no-cache upgrade
USER 101

# Custom SPA config (static only; no /api proxy).
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the built assets from the build stage.
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080

