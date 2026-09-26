# pixnest frontend

A small photo-gallery UI for the pixnest app. Built with Vite, React 18,
TypeScript, Tailwind CSS, and TanStack Query.

## Requirements

- Node.js 20 or newer
- The pixnest backend (FastAPI) running for a fully working app

## Local development

```bash
npm install
npm run dev
```

This starts the Vite dev server (default http://localhost:5173). The dev
server proxies `/api` to `http://localhost:8000`, so run the backend there and
the app works with no CORS setup. See the proxy config in `vite.config.ts`.

## Build

```bash
npm run build
```

The static site is written to `dist/`. Preview the production build locally
with:

```bash
npm run preview
```

## How it talks to the backend

The frontend expects the backend under `/api` on the same origin:

- In development, the Vite dev-server proxy forwards `/api` to the backend.
- In production, the app is served as static files by nginx and a Kubernetes
  Ingress routes `/api` to the backend. The production nginx does not proxy
  `/api`.

Endpoints used. All of them send the stored JWT as a bearer token, and all of them
answer 401 without one:

- `GET /api/photos` - list the signed-in user's own photos, newest first
- `POST /api/photos` - upload one image as multipart `file`
- `DELETE /api/photos/{id}` - delete a photo

The gallery is rendered only while signed in, its React Query cache key includes the
username, and signing out clears the cache. Otherwise the next person to sign in on the
same browser would see the previous user's photos from cache before their own arrived.

## Production image

A multi-stage `Dockerfile` builds the static assets with `node:20-slim` and
serves them with `nginxinc/nginx-unprivileged` on port 8080 (non-root), using
the SPA config in `nginx.conf`.

```bash
docker build -t pixnest-frontend .
docker run --rm -p 8080:8080 pixnest-frontend
```

