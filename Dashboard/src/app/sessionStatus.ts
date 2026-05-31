export function formatSecureSessionStatus(pid: number | string | null | undefined): string {
  const normalizedPid = String(pid ?? "").trim();
  return `[>_ SECURE_SESSION_ACTIVE // PID: ${normalizedPid || "..."}]`;
}
