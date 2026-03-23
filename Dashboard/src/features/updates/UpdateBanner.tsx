import React, { useEffect, useState } from "react";
import { UpdateStatus } from "./useUpdateCheck";

interface Props {
  status: UpdateStatus;
}

const HIDDEN_VERSION_KEY = "sloppy_hidden_release_version";

function isNewer(candidate: string, than: string): boolean {
  const parse = (v: string) => v.split(".").map((n) => parseInt(n, 10) || 0);
  const a = parse(candidate);
  const b = parse(than);
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    const av = a[i] ?? 0;
    const bv = b[i] ?? 0;
    if (av > bv) return true;
    if (av < bv) return false;
  }
  return false;
}

export function UpdateBanner({ status }: Props) {
  const [hiddenVersion, setHiddenVersion] = useState<string>(() => {
    return localStorage.getItem(HIDDEN_VERSION_KEY) ?? "";
  });

  useEffect(() => {
    const stored = localStorage.getItem(HIDDEN_VERSION_KEY) ?? "";
    setHiddenVersion(stored);
  }, [status.latestVersion]);

  if (!status.isReleaseBuild) return null;
  if (!status.updateAvailable) return null;
  if (!status.latestVersion) return null;
  if (!isNewer(status.latestVersion, hiddenVersion)) return null;

  function dismiss() {
    if (!status.latestVersion) return;
    localStorage.setItem(HIDDEN_VERSION_KEY, status.latestVersion);
    setHiddenVersion(status.latestVersion);
  }

  return (
    <div className="update-banner">
      <span className="material-symbols-rounded update-banner-icon" aria-hidden="true">
        system_update
      </span>
      <span className="update-banner-text">
        <strong>Version {status.latestVersion} is available</strong>
        <span className="update-banner-current">(current: {status.currentVersion})</span>
      </span>
      <div className="update-banner-actions">
        {status.releaseUrl && (
          <a
            href={status.releaseUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="update-banner-learn-more"
          >
            Learn More
          </a>
        )}
        <button
          type="button"
          className="update-banner-close"
          onClick={dismiss}
          aria-label="Dismiss update notification"
        >
          <span className="material-symbols-rounded" aria-hidden="true">close</span>
        </button>
      </div>
    </div>
  );
}
