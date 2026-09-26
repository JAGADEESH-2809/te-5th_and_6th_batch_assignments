import { useCallback, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { clearSession, getSession, type AuthSession } from "./api";
import { AuthPanel } from "./components/AuthPanel";
import { Gallery } from "./components/Gallery";
import { Header } from "./components/Header";
import { UploadArea } from "./components/UploadArea";

// Top-level layout: header, then either the vault (upload area + your gallery)
// when signed in, or the sign-in panel when not. Nothing about someone's photos
// is reachable without a session.
export default function App() {
  const queryClient = useQueryClient();
  const [session, setSession] = useState<AuthSession | null>(getSession());

  // Signing out has to clear the cache as well as the token. React Query would
  // otherwise keep the fetched photos in memory, and the next person to sign in on
  // this browser would see the previous user's gallery from cache for a moment
  // before their own request came back.
  const signOut = useCallback(() => {
    clearSession();
    setSession(null);
    queryClient.clear();
  }, [queryClient]);

  const signIn = useCallback(
    (next: AuthSession) => {
      queryClient.clear();
      setSession(next);
    },
    [queryClient],
  );

  return (
    <div className="min-h-screen bg-neutral-50">
      <Header username={session?.username ?? null} onSignOut={signOut} />
      <main className="mx-auto max-w-5xl space-y-8 px-4 py-8">
        {session ? (
          <>
            <UploadArea />
            <Gallery currentUser={session.username} onSessionExpired={signOut} />
          </>
        ) : (
          <AuthPanel onSignedIn={signIn} />
        )}
      </main>
    </div>
  );
}
