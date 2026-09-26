export function Header({
  username,
  onSignOut,
}: {
  username: string | null;
  onSignOut: () => void;
}) {
  return (
    <header className="border-b border-emerald-100 bg-[#f7faf5]">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-5">
        <div>
         <h1 className="flex items-center gap-2 text-2xl font-semibold tracking-tight text-emerald-900">
  <span className="text-lg">🌿</span>
  PixNest
</h1>

          <p className="mt-1 text-sm text-stone-500">
            A simple place to keep your favorite memories.
          </p>
        </div>

        {username && (
          <div className="flex items-center gap-3">
            <span className="hidden text-sm text-stone-600 sm:block">
              Hi, <span className="font-medium text-emerald-800">{username}</span>
            </span>

            <button
              type="button"
              onClick={onSignOut}
              className="rounded-lg border border-emerald-200 bg-white px-3 py-1.5 text-sm font-medium text-emerald-800 transition-colors hover:bg-emerald-50"
            >
              Sign out
            </button>
          </div>
        )}
      </div>
    </header>
  );
}