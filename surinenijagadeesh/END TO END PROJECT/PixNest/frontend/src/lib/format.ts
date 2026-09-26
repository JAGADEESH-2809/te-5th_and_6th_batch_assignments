// Convert a byte count into a short human-readable string, e.g. "1.2 MB".
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";

  const units = ["B", "KB", "MB", "GB", "TB"];
  const exponent = Math.min(
    Math.floor(Math.log(bytes) / Math.log(1024)),
    units.length - 1,
  );
  const value = bytes / Math.pow(1024, exponent);

  // Show no decimals for plain bytes, one decimal for larger units.
  const rounded = exponent === 0 ? value.toFixed(0) : value.toFixed(1);
  return `${rounded} ${units[exponent]}`;
}
