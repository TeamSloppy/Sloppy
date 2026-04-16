import { useCallback, useEffect, useRef, useState } from "react";
import { fetchUpdateStatus, forceUpdateCheck } from "../../api";

export interface UpdateStatus {
  currentVersion: string;
  latestVersion: string | null;
  updateAvailable: boolean;
  releaseUrl: string | null;
  publishedAt: string | null;
  lastCheckedAt: string | null;
  isReleaseBuild: boolean;
  deploymentKind: "docker" | "local";
  currentCommit: string | null;
  currentBranch: string | null;
  currentCommitDate: string | null;
  latestCommit: string | null;
  latestCommitDate: string | null;
  latestBranch: string | null;
  updateKind: "release" | "git";
}

interface UseUpdateCheckResult {
  status: UpdateStatus | null;
  isChecking: boolean;
  forceCheck: () => Promise<void>;
}

const POLL_INTERVAL_MS = 30 * 60 * 1000;

function parseStatus(raw: Record<string, unknown>): UpdateStatus {
  return {
    currentVersion: String(raw.currentVersion ?? ""),
    latestVersion: raw.latestVersion != null ? String(raw.latestVersion) : null,
    updateAvailable: Boolean(raw.updateAvailable),
    releaseUrl: raw.releaseUrl != null ? String(raw.releaseUrl) : null,
    publishedAt: raw.publishedAt != null ? String(raw.publishedAt) : null,
    lastCheckedAt: raw.lastCheckedAt != null ? String(raw.lastCheckedAt) : null,
    isReleaseBuild: Boolean(raw.isReleaseBuild),
    deploymentKind: raw.deploymentKind === "docker" ? "docker" : "local",
    currentCommit: raw.currentCommit != null ? String(raw.currentCommit) : null,
    currentBranch: raw.currentBranch != null ? String(raw.currentBranch) : null,
    currentCommitDate: raw.currentCommitDate != null ? String(raw.currentCommitDate) : null,
    latestCommit: raw.latestCommit != null ? String(raw.latestCommit) : null,
    latestCommitDate: raw.latestCommitDate != null ? String(raw.latestCommitDate) : null,
    latestBranch: raw.latestBranch != null ? String(raw.latestBranch) : null,
    updateKind: raw.updateKind === "release" ? "release" : "git",
  };
}

export function useUpdateCheck(): UseUpdateCheckResult {
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [isChecking, setIsChecking] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const load = useCallback(async () => {
    const raw = await fetchUpdateStatus();
    if (raw) {
      setStatus(parseStatus(raw as Record<string, unknown>));
    }
  }, []);

  const forceCheck = useCallback(async () => {
    setIsChecking(true);
    try {
      const raw = await forceUpdateCheck();
      if (raw) {
        setStatus(parseStatus(raw as Record<string, unknown>));
      }
    } finally {
      setIsChecking(false);
    }
  }, []);

  useEffect(() => {
    load();
    intervalRef.current = setInterval(load, POLL_INTERVAL_MS);
    return () => {
      if (intervalRef.current !== null) {
        clearInterval(intervalRef.current);
      }
    };
  }, [load]);

  return { status, isChecking, forceCheck };
}
