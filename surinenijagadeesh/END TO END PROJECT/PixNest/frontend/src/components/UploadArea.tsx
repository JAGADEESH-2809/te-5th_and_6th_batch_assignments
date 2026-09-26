import { useRef, useState, type DragEvent } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { uploadPhoto } from "../api";
import { formatBytes } from "../lib/format";
import { Spinner } from "./Spinner";

// Client-side guardrails that mirror the backend limits. The backend is still
// the source of truth (415 / 413); these just give faster feedback.
const MAX_BYTES = 10 * 1024 * 1024; // 10 MB

// Upload area: pick or drop an image, review it, then submit. Uses a
// useMutation and invalidates the photo list on success.
export function UploadArea() {
  const queryClient = useQueryClient();
  const inputRef = useRef<HTMLInputElement>(null);

  const [file, setFile] = useState<File | null>(null);
  const [localError, setLocalError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);

  const mutation = useMutation({
    mutationFn: uploadPhoto,
    onSuccess: () => {
      // Refresh the gallery and clear the form.
      queryClient.invalidateQueries({ queryKey: ["photos"] });
      setFile(null);
      if (inputRef.current) inputRef.current.value = "";
    },
  });

  // Validate a candidate file before we allow submitting it.
  function selectFile(candidate: File | undefined) {
    setLocalError(null);
    mutation.reset();
    if (!candidate) return;

    if (!candidate.type.startsWith("image/")) {
      setLocalError("Unsupported type. Please choose an image file.");
      return;
    }
    if (candidate.size > MAX_BYTES) {
      setLocalError("File too large. The limit is 10 MB.");
      return;
    }
    setFile(candidate);
  }

  function onDrop(e: DragEvent<HTMLDivElement>) {
    e.preventDefault();
    setDragging(false);
    selectFile(e.dataTransfer.files?.[0]);
  }

  function onSubmit() {
    if (file) mutation.mutate(file);
  }

  // Prefer the local validation message, then any backend error.
  const errorText =
    localError ?? (mutation.isError ? mutation.error.message : null);

  return (
    <section className="rounded-2xl border border-emerald-100 bg-[#fffdf8] p-5 shadow-sm">
      <div
        onDragOver={(e) => {
          e.preventDefault();
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        className={`flex min-h-56 flex-col items-center justify-center rounded-xl border-2 border-dashed px-6 py-10 text-center transition-colors ${
  dragging
    ? "border-emerald-400 bg-emerald-50"
    : "border-emerald-100 bg-[#f7f8f3]"
}`}
      >
        <p className="text-sm text-stone-600">
          Drag and drop an image here, or
        </p>

        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="mt-3 rounded-lg border border-emerald-200 bg-white px-4 py-2 text-sm font-medium text-emerald-800 shadow-sm transition-colors hover:bg-emerald-50"
        >
          Choose file
        </button>

        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => selectFile(e.target.files?.[0])}
        />

        <p className="mt-3 text-xs text-stone-400">
          Images only, up to 10 MB.
        </p>
      </div>

      {/* Selected file preview and submit control. */}
      {file && (
        <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-neutral-800">
              {file.name}
            </p>
            <p className="text-xs text-neutral-500">{formatBytes(file.size)}</p>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => selectFile(undefined)}
              disabled={mutation.isPending}
              className="rounded-md px-3 py-2 text-sm font-medium text-neutral-600 transition-colors hover:bg-neutral-100 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={onSubmit}
              disabled={mutation.isPending}
              className="inline-flex items-center gap-2 rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white shadow-sm transition-colors hover:bg-neutral-700 disabled:opacity-60"
            >
              {mutation.isPending && <Spinner />}
              {mutation.isPending ? "Uploading" : "Upload"}
            </button>
          </div>
        </div>
      )}

      {errorText && (
        <p className="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          {errorText}
        </p>
      )}
    </section>
  );
}
