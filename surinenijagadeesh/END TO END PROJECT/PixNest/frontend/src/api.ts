// API client for the pixnest backend. The frontend talks to the FastAPI
// app at the same origin under /api (dev via Vite proxy, prod via Ingress).

// Shape of a photo as returned by the backend.
export interface PhotoOut {
  id: string;
  filename: string;
  content_type: string;
  size_bytes: number;
  uploaded_by: string | null;
  uploaded_at: string;
  // Short-lived presigned S3 URL used to display the image.
  url: string;
}

const API_BASE = "/api";

// ---------------------------------------------------------------------------
// Auth: self-issued JWTs from the backend. The session (token + username) is
// kept in localStorage; wrap all storage access in try/catch (private mode).
// ---------------------------------------------------------------------------
const SESSION_KEY = "pixnest.session";

export interface AuthSession {
  token: string;
  username: string;
}

export function getSession(): AuthSession | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    return raw ? (JSON.parse(raw) as AuthSession) : null;
  } catch {
    return null;
  }
}

export function clearSession(): void {
  try {
    localStorage.removeItem(SESSION_KEY);
  } catch {
    // ignore
  }
}

function saveSession(session: AuthSession): void {
  try {
    localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  } catch {
    // ignore
  }
}

function authHeaders(): Record<string, string> {
  const session = getSession();
  return session ? { Authorization: `Bearer ${session.token}` } : {};
}

// POST /api/auth/register -> 201 (409 if the name is taken).
export async function register(username: string, password: string): Promise<void> {
  const res = await fetch(`${API_BASE}/auth/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error(await errorMessage(res));
}

// POST /api/auth/login (form-encoded, OAuth2 password flow) -> JWT.
export async function login(username: string, password: string): Promise<AuthSession> {
  const res = await fetch(`${API_BASE}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ username, password }),
  });
  if (!res.ok) throw new Error(await errorMessage(res));
  const data = await res.json();
  const session: AuthSession = { token: data.access_token, username };
  saveSession(session);
  return session;
}

// Raised when the backend rejects the token: absent, malformed, or expired. The UI
// treats this as "your session ended", drops the stored session, and shows sign in
// again, rather than leaving a confusing red error box on screen.
export class UnauthorizedError extends Error {}

// Turn a failed response into the right kind of Error to throw.
async function failure(res: Response): Promise<Error> {
  const message = await errorMessage(res);
  return res.status === 401 ? new UnauthorizedError(message) : new Error(message);
}

// Pull a useful message out of a failed response. FastAPI reports errors as
// { "detail": ... }, so we try that first and fall back to the status text.
async function errorMessage(res: Response): Promise<string> {
  try {
    const data = await res.json();
    if (typeof data?.detail === "string") return data.detail;
    if (Array.isArray(data?.detail) && data.detail[0]?.msg) {
      return data.detail[0].msg;
    }
  } catch {
    // Body was not JSON; fall through to the generic message below.
  }
  return `Request failed (${res.status} ${res.statusText})`;
}

// GET /api/photos -> the signed-in user's own photos, newest first, paginated.
// The token is required and also decides whose photos come back, so there is no
// user parameter here to get wrong.
export async function fetchPhotos(limit = 50, offset = 0): Promise<PhotoOut[]> {
  const res = await fetch(`${API_BASE}/photos?limit=${limit}&offset=${offset}`, {
    headers: authHeaders(),
  });
  if (!res.ok) throw await failure(res);
  return res.json();
}

// POST /api/photos -> multipart/form-data with a single "file" field.
export async function uploadPhoto(file: File): Promise<PhotoOut> {
  const form = new FormData();
  form.append("file", file);

  const res = await fetch(`${API_BASE}/photos`, {
    method: "POST",
    headers: authHeaders(),
    body: form,
  });
  if (!res.ok) throw await failure(res);
  return res.json();
}

// DELETE /api/photos/{id} -> 204 No Content.
export async function deletePhoto(id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/photos/${id}`, {
    method: "DELETE",
    headers: authHeaders(),
  });
  if (!res.ok) throw await failure(res);
}

