import React, { useState } from "react";
import { UpdateStatus } from "./useUpdateCheck";

interface Props {
  status: UpdateStatus | null;
  isChecking: boolean;
  onForceCheck: () => Promise<void>;
}

function formatDate(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleString();
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  function handleCopy() {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }).catch(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  return (
    <button type="button" className="updates-copy-btn" onClick={handleCopy}>
      {copied ? "Copied" : "Copy"}
    </button>
  );
}

function CommandBlock({ label, command }: { label: string; command: string }) {
  return (
    <div className="updates-command-block">
      <div className="updates-command-label">
        <span>{label}</span>
        <CopyButton text={command} />
      </div>
      <pre className="updates-command-pre">{command}</pre>
    </div>
  );
}

const DOCKER_COMPOSE_CMD = `docker compose pull sloppy\ndocker compose up -d --force-recreate sloppy`;
const DOCKER_RUN_CMD = `docker pull ghcr.io/teamsloppy/sloppy:latest\ndocker stop sloppy && docker rm sloppy\ndocker run -d --name sloppy -p 25101:25101 ghcr.io/teamsloppy/sloppy:latest`;

export function UpdatesView({ status, isChecking, onForceCheck }: Props) {
  const currentVersion = status?.currentVersion ?? "—";
  const latestVersion = status?.latestVersion ?? "—";
  const lastChecked = formatDate(status?.lastCheckedAt ?? null);
  const updateAvailable = status?.updateAvailable ?? false;
  const isReleaseBuild = status?.isReleaseBuild ?? false;
  const releaseUrl = status?.releaseUrl;

  return (
    <div className="updates-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>Updates</h3>
        <p className="placeholder-text">
          Check release status, trigger one-click Docker updates, and copy manual update commands.
        </p>
      </section>

      <section className="entry-editor-card">
        <div className="updates-section-header">
          <h4>Release Status</h4>
          {updateAvailable && isReleaseBuild && (
            <span className="updates-badge-new">Update {latestVersion} is available</span>
          )}
        </div>

        <div className="updates-status-grid">
          <div className="updates-status-item">
            <span className="updates-status-label">Deployment</span>
            <span className="updates-status-value">Docker</span>
          </div>
          <div className="updates-status-item">
            <span className="updates-status-label">Current version</span>
            <span className="updates-status-value updates-status-mono">
              {isReleaseBuild ? currentVersion : `${currentVersion} (dev)`}
            </span>
          </div>
          <div className="updates-status-item">
            <span className="updates-status-label">Latest release</span>
            <span className="updates-status-value updates-status-mono">
              {isReleaseBuild ? latestVersion : "—"}
            </span>
          </div>
          <div className="updates-status-item">
            <span className="updates-status-label">Last checked</span>
            <span className="updates-status-value">{isReleaseBuild ? lastChecked : "—"}</span>
          </div>
        </div>

        <div className="updates-status-actions">
          <button
            type="button"
            className="updates-check-btn"
            onClick={onForceCheck}
            disabled={isChecking || !isReleaseBuild}
          >
            {isChecking ? "Checking..." : "Check now"}
          </button>
          {releaseUrl && (
            <a
              href={releaseUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="updates-release-link"
            >
              View release notes
            </a>
          )}
        </div>
      </section>

      <section className="entry-editor-card">
        <h4>One-Click Docker Update</h4>
        <p className="placeholder-text">Pull and swap to the latest release image from the web UI.</p>
        <div className="updates-oneclick-row">
          <a
            href="https://docs.docker.com/engine/install/"
            target="_blank"
            rel="noopener noreferrer"
            className="updates-docker-sock-hint"
          >
            Mount /var/run/docker.sock to enable one-click updates.
          </a>
          <button type="button" className="updates-update-now-btn" disabled>
            Update now
          </button>
        </div>
      </section>

      <section className="entry-editor-card">
        <h4>Manual Update Commands</h4>
        <p className="placeholder-text">
          Use these when one-click update is unavailable or when you prefer manual rollouts.
        </p>

        <CommandBlock label="DOCKER COMPOSE" command={DOCKER_COMPOSE_CMD} />
        <CommandBlock label="DOCKER RUN" command={DOCKER_RUN_CMD} />
      </section>
    </div>
  );
}
