import { useState, type FormEvent } from "react";
import { login, register, type AuthSession } from "../api";
import { Spinner } from "./Spinner";

// Sign in / create account form. On success, hands the session up to App.
export function AuthPanel({ onSignedIn }: { onSignedIn: (s: AuthSession) => void }) {
  const [mode, setMode] = useState<"signin" | "register">("signin");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      if (mode === "register") {
        await register(username, password);
      }
      onSignedIn(await login(username, password));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="rounded-xl border border-neutral-200 bg-white p-5 shadow-sm">
      <div className="mx-auto max-w-sm">
        <h2 className="text-base font-semibold text-neutral-900">
          {mode === "signin" ? "Sign in to your vault" : "Create an account"}
        </h2>
        <p className="mt-1 text-xs text-neutral-500">
          Your photos are private. Sign in to see and upload them.
        </p>

        <form onSubmit={onSubmit} className="mt-4 space-y-3">
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="Username"
            autoComplete="username"
            required
            minLength={3}
            className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-900 focus:outline-none"
          />
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Password (min 8 characters)"
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
            required
            minLength={8}
            maxLength={72}
            className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-900 focus:outline-none"
          />

          <button
            type="submit"
            disabled={busy}
            className="inline-flex w-full items-center justify-center gap-2 rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white shadow-sm transition-colors hover:bg-neutral-700 disabled:opacity-60"
          >
            {busy && <Spinner />}
            {mode === "signin" ? "Sign in" : "Create account"}
          </button>
        </form>

        {error && (
          <p className="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
            {error}
          </p>
        )}

        <button
          type="button"
          onClick={() => {
            setMode(mode === "signin" ? "register" : "signin");
            setError(null);
          }}
          className="mt-3 text-xs font-medium text-neutral-600 underline-offset-2 hover:underline"
        >
          {mode === "signin"
            ? "No account? Create one"
            : "Already have an account? Sign in"}
        </button>
      </div>
    </section>
  );
}
