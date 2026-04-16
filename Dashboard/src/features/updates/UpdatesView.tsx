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
  const isDockerDeployment = status?.deploymentKind === "docker";
  const isGitBuild = status?.updateKind === "git";
  const currentCommitDate = formatDate(status?.currentCommitDate ?? null);
  const latestCommitDate = formatDate(status?.latestCommitDate ?? null);
  const latestCommit = status?.latestCommit ?? "—";
  const latestBranch = status?.latestBranch ?? status?.currentBranch ?? "—";

  return (
    <div className="updates-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>Updates</h3>
        <p className="placeholder-text">
          Check release or upstream branch status and review the current build metadata.
        </p>
      </section>

      <section className="entry-editor-card">
        <div className="updates-section-header">
          <h4>{isGitBuild ? "Git Status" : "Release Status"}</h4>
          {updateAvailable && isReleaseBuild && (
            <span className="updates-badge-new">Update {latestVersion} is available</span>
          )}
          {updateAvailable && isGitBuild && (
            <span className="updates-badge-new">
              Upstream {latestBranch} has a newer commit
            </span>
          )}
        </div>

        <div className="updates-status-grid">
          {isDockerDeployment && (
            <div className="updates-status-item">
              <span className="updates-status-label">Deployment</span>
              <span className="updates-status-value">Docker</span>
            </div>
          )}
          <div className="updates-status-item">
            <span className="updates-status-label">{isGitBuild ? "Current build" : "Current version"}</span>
            <span className="updates-status-value updates-status-mono">
              {currentVersion}
            </span>
          </div>
          {isReleaseBuild ? (
            <div className="updates-status-item">
              <span className="updates-status-label">Latest release</span>
              <span className="updates-status-value updates-status-mono">{latestVersion}</span>
            </div>
          ) : (
            <div className="updates-status-item">
              <span className="updates-status-label">Latest upstream commit</span>
              <span className="updates-status-value updates-status-mono">
                {latestCommit === "—" ? "—" : `${latestCommit} (${latestBranch})`}
              </span>
            </div>
          )}
          <div className="updates-status-item">
            <span className="updates-status-label">{isGitBuild ? "Current commit date" : "Last checked"}</span>
            <span className="updates-status-value">{isGitBuild ? currentCommitDate : lastChecked}</span>
          </div>
          {isGitBuild && (
            <div className="updates-status-item">
              <span className="updates-status-label">Latest commit date</span>
              <span className="updates-status-value">{latestCommitDate}</span>
            </div>
          )}
          {isGitBuild && status?.lastCheckedAt && (
            <div className="updates-status-item">
              <span className="updates-status-label">Last checked</span>
              <span className="updates-status-value">{lastChecked}</span>
            </div>
          )}
          {!isReleaseBuild && !status?.latestCommit && (
            <div className="updates-status-item">
              <span className="updates-status-label">Tracking branch</span>
              <span className="updates-status-value updates-status-mono">{latestBranch}</span>
            </div>
          )}
          {!isReleaseBuild && !status?.latestBranch && (
            <div className="updates-status-item">
              <span className="updates-status-label">Remote status</span>
              <span className="updates-status-value">Unavailable</span>
            </div>
          )}
          {!isReleaseBuild && !status?.latestCommit && !status?.currentCommitDate && (
            <div className="updates-status-item">
              <span className="updates-status-label">Source metadata</span>
              <span className="updates-status-value">Git metadata unavailable</span>
            </div>
          )}
          {!isReleaseBuild && status?.currentCommit && !status?.currentBranch && (
            <div className="updates-status-item">
              <span className="updates-status-label">Commit</span>
              <span className="updates-status-value updates-status-mono">{status.currentCommit}</span>
            </div>
          )}
          {!isReleaseBuild && status?.currentBranch && (
            <div className="updates-status-item">
              <span className="updates-status-label">Branch</span>
              <span className="updates-status-value updates-status-mono">{status.currentBranch}</span>
            </div>
          )}
          {!isReleaseBuild && !status?.latestCommit && !status?.latestBranch && (
            <div className="updates-status-item">
              <span className="updates-status-label">Upstream</span>
              <span className="updates-status-value">Not configured</span>
            </div>
          )}
        </div>

        <div className="updates-status-actions">
          <button
            type="button"
            className="updates-check-btn"
            onClick={onForceCheck}
            disabled={isChecking}
          >
            {isChecking ? "Checking..." : "Check now"}
          </button>
          {releaseUrl && isReleaseBuild && (
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

      {isDockerDeployment && (
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
      )}

      {isDockerDeployment && (
        <section className="entry-editor-card">
          <h4>Manual Update Commands</h4>
          <p className="placeholder-text">
            Use these when one-click update is unavailable or when you prefer manual rollouts.
          </p>

          <CommandBlock label="DOCKER COMPOSE" command={DOCKER_COMPOSE_CMD} />
          <CommandBlock label="DOCKER RUN" command={DOCKER_RUN_CMD} />
        </section>
      )}
    </div>
  );
}
