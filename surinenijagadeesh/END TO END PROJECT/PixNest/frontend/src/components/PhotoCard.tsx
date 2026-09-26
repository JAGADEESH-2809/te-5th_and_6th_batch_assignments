import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { deletePhoto, type PhotoOut } from "../api";
import { formatBytes } from "../lib/format";
import { Spinner } from "./Spinner";

// A single photo card: image, filename, size, uploader, and (for the owner) a
// delete button with a two// -step confirm; the armed state resets after a few seconds.

export function PhotoCard({
  photo,
  currentUser,
}: {
  photo: PhotoOut;
  currentUser: string | null;
}) {
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);

  // Only the uploader may delete (legacy ownerless photos: any signed-in user).
  const canDelete =
    currentUser !== null &&
    (!photo.uploaded_by || photo.uploaded_by === currentUser);

  useEffect(() => {
    if (!confirming) return;
    const t = setTimeout(() => setConfirming(false), 3000);
    return () => clearTimeout(t);
  }, [confirming]);

  const mutation = useMutation({
    mutationFn: () => deletePhoto(photo.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["photos"] });
    },
  });

  function handleDeleteClick() {
    if (!confirming) {
      setConfirming(true);
      return;
    }
    setConfirming(false);
    mutation.mutate();
  }

  return (
    <div className="group overflow-hidden rounded-2xl border border-emerald-100 bg-[#fffdf8] shadow-sm transition-shadow hover:shadow-md">
      <div className="aspect-square overflow-hidden bg-[#eef1e8]">
        <img
          src={photo.url}
          alt={photo.filename}
          loading="lazy"
          className="h-full w-full object-cover"
        />
      </div>

      <div className="flex items-center justify-between gap-2 p-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-emerald-950">
            {photo.filename}
          </p>
         <p className="text-xs text-stone-500">
            {formatBytes(photo.size_bytes)}
            {photo.uploaded_by && (
              <span className="text-stone-400"> - by {photo.uploaded_by}</span>
            )}
          </p>
        </div>

        {canDelete && (
        <button
          type="button"
          onClick={handleDeleteClick}
          disabled={mutation.isPending}
          aria-label={
            confirming
              ? `Confirm delete ${photo.filename}`
              : `Delete ${photo.filename}`
          }
          className={
            confirming
              ? "inline-flex shrink-0 items-center rounded-md bg-red-600 px-2 py-1.5 text-sm font-medium text-white transition-colors hover:bg-red-700 disabled:opacity-50"
              : "inline-flex shrink-0 items-center rounded-lg px-2 py-1.5 text-sm font-medium text-rose-600 transition-colors hover:bg-rose-50 disabled:opacity-50"
          }
        >
          {mutation.isPending ? (
            <Spinner className="text-red-600" />
          ) : confirming ? (
            "Confirm?"
          ) : (
            "Delete"
          )}
        </button>
        )}
      </div>

      {mutation.isError && (
        <p className="px-3 pb-3 text-xs text-red-600">
          {mutation.error.message}
        </p>
      )}
    </div>
  );
}
