/// Compact human-readable size for download progress (e.g. `3.2 MB`).
String formatByteSize(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
