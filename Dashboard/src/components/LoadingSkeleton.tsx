import React from "react";

type LoadingSkeletonVariant = "panel" | "page" | "cards" | "list" | "graph" | "code";

interface LoadingSkeletonProps {
  label?: string;
  variant?: LoadingSkeletonVariant;
  rows?: number;
  cards?: number;
  className?: string;
}

function cx(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(" ");
}

export function LoadingSkeleton({
  label = "Loading…",
  variant = "panel",
  rows = 3,
  cards = 3,
  className = ""
}: LoadingSkeletonProps) {
  const rowItems = Array.from({ length: Math.max(1, rows) });
  const cardItems = Array.from({ length: Math.max(1, cards) });

  if (variant === "cards") {
    return (
      <div className={cx("loading-skeleton loading-skeleton--cards", className)} role="status" aria-live="polite" aria-busy="true">
        <span className="loading-skeleton__label">{label}</span>
        <div className="loading-skeleton__card-grid">
          {cardItems.map((_, index) => (
            <div className="loading-skeleton__card" key={index}>
              <span className="loading-skeleton__avatar" />
              <span className="loading-skeleton__line loading-skeleton__line--strong" />
              <span className="loading-skeleton__line" />
              <span className="loading-skeleton__line loading-skeleton__line--short" />
              <div className="loading-skeleton__chips">
                <span />
                <span />
                <span />
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (variant === "page") {
    return (
      <div className={cx("loading-skeleton loading-skeleton--page", className)} role="status" aria-live="polite" aria-busy="true">
        <span className="loading-skeleton__label">{label}</span>
        <div className="loading-skeleton__hero">
          <span className="loading-skeleton__avatar loading-skeleton__avatar--large" />
          <div>
            <span className="loading-skeleton__line loading-skeleton__line--title" />
            <span className="loading-skeleton__line" />
          </div>
        </div>
        <div className="loading-skeleton__page-grid">
          <div className="loading-skeleton__panel">{rowItems.map((_, i) => <span key={i} className="loading-skeleton__line" />)}</div>
          <div className="loading-skeleton__panel loading-skeleton__panel--wide">{Array.from({ length: rows + 2 }).map((_, i) => <span key={i} className="loading-skeleton__line" />)}</div>
        </div>
      </div>
    );
  }

  if (variant === "graph") {
    return (
      <div className={cx("loading-skeleton loading-skeleton--graph", className)} role="status" aria-live="polite" aria-busy="true">
        <span className="loading-skeleton__label">{label}</span>
        <div className="loading-skeleton__graph-canvas">
          <span className="loading-skeleton__node loading-skeleton__node--a" />
          <span className="loading-skeleton__node loading-skeleton__node--b" />
          <span className="loading-skeleton__node loading-skeleton__node--c" />
          <span className="loading-skeleton__edge loading-skeleton__edge--a" />
          <span className="loading-skeleton__edge loading-skeleton__edge--b" />
        </div>
      </div>
    );
  }

  if (variant === "code") {
    return (
      <div className={cx("loading-skeleton loading-skeleton--code", className)} role="status" aria-live="polite" aria-busy="true">
        <span className="loading-skeleton__label">{label}</span>
        {Array.from({ length: Math.max(4, rows) }).map((_, index) => (
          <span key={index} className={cx("loading-skeleton__line", index % 3 === 2 && "loading-skeleton__line--short")} />
        ))}
      </div>
    );
  }

  return (
    <div className={cx("loading-skeleton", variant === "list" && "loading-skeleton--list", className)} role="status" aria-live="polite" aria-busy="true">
      <span className="loading-skeleton__label">{label}</span>
      {rowItems.map((_, index) => (
        <div className="loading-skeleton__row" key={index}>
          {variant === "list" ? <span className="loading-skeleton__avatar" /> : null}
          <div>
            <span className="loading-skeleton__line loading-skeleton__line--strong" />
            <span className="loading-skeleton__line" />
          </div>
        </div>
      ))}
    </div>
  );
}
