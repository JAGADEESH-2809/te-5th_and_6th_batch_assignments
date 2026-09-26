import { useEffect } from "react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { fetchPhotos, UnauthorizedError } from "../api";
import { PhotoCard } from "./PhotoCard";
import { Spinner } from "./Spinner";

const PAGE_SIZE = 24;

// Grid of the signed-in user's own photos, with loading, error, and empty states.
// Pages through the list (the backend paginates) with a "Load more" button.
export function Gallery({
  currentUser,
  onSessionExpired,
}: {
  currentUser: string;
  onSessionExpired: () => void;
}) {
  const {
    data,
    isPending,
    isError,
    error,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
  } = useInfiniteQuery({
    // The username is part of the key. These photos belong to one person, so two
    // users on the same browser must never share a cache entry.
    queryKey: ["photos", currentUser],
    queryFn: ({ pageParam }) => fetchPhotos(PAGE_SIZE, pageParam),
    initialPageParam: 0,
    getNextPageParam: (lastPage, _pages, lastOffset) =>
      lastPage.length === PAGE_SIZE ? lastOffset + PAGE_SIZE : undefined,
    // Retrying a rejected token just fails again more slowly.
    retry: (count, err) => !(err instanceof UnauthorizedError) && count < 2,
  });

  // Tokens expire. When one does while the tab is open, end the session and return
  // to the sign-in panel, instead of showing an error the user cannot act on.
  useEffect(() => {
    if (isError && error instanceof UnauthorizedError) onSessionExpired();
  }, [isError, error, onSessionExpired]);

  if (isPending) {
    return (
      <div className="flex items-center justify-center gap-2 py-16 text-neutral-500">
        <Spinner />
        <span className="text-sm">Loading photos</span>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-10 text-center">
        <p className="text-sm font-medium text-red-700">
          Could not load photos.
        </p>
        <p className="mt-1 text-xs text-red-600">{error.message}</p>
      </div>
    );
  }

  const photos = data.pages.flat();

  if (photos.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-emerald-200 bg-[#fffdf8] px-4 py-16 text-center">
        <p className="text-sm font-medium text-emerald-900">
          No photos in your vault yet
        </p>
        <p className="mt-1 text-xs text-stone-500">
  Upload a photo above and start keeping your memories here.
</p>
      </div>
    );
  }

  return (
    <div>
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {photos.map((photo) => (
          <PhotoCard key={photo.id} photo={photo} currentUser={currentUser} />
        ))}
      </div>

      {hasNextPage && (
        <div className="mt-6 flex justify-center">
          <button
            type="button"
            onClick={() => fetchNextPage()}
            disabled={isFetchingNextPage}
            className="inline-flex items-center gap-2 rounded-lg border border-emerald-200 bg-white px-4 py-2 text-sm font-medium text-emerald-800 transition-colors hover:bg-emerald-50 disabled:opacity-50"
          >
            {isFetchingNextPage && <Spinner />}
            Load more
          </button>
        </div>
      )}
    </div>
  );
}
