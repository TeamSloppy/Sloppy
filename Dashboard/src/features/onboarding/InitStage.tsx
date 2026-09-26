import type { ReactNode } from "react";

interface InitStageProps {
  children: ReactNode;
  state?: "loading" | "editing" | "error";
}

type InitStageState = NonNullable<InitStageProps["state"]>;

function Cube({ x, y, scale = 1, accent = false, delay = 0 }: { x: number; y: number; scale?: number; accent?: boolean; delay?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`}>
      <g className={`init-geometry-cube ${accent ? "init-geometry-cube--accent" : ""}`} style={{ animationDelay: `${delay}s` }}>
        <path className="init-geometry-face init-geometry-face--top" d="M0 -91 126 -28 0 35 -126 -28Z" />
        <path className="init-geometry-face init-geometry-face--left" d="M-126 -28 0 35 0 158 -126 95Z" />
        <path className="init-geometry-face init-geometry-face--right" d="M0 35 126 -28 126 95 0 158Z" />
        <path className="init-geometry-edge" d="M0 -91 126 -28 126 95 0 158 -126 95 -126 -28Z M-126 -28 0 35 126 -28 M0 35V158" />
      </g>
    </g>
  );
}

function InitGeometry({ state }: { state: InitStageState }) {
  const statusLabel = state === "error" ? "CONNECTION LOST" : state === "editing" ? "SERVER SETUP" : "INITIALIZING";
  return (
    <div className="init-stage-visual" aria-hidden="true">
      <div className="init-stage-visual-top"><span>01 / CORE</span><span>{statusLabel}</span></div>
      <svg className="init-geometry" viewBox="0 0 760 620" focusable="false">
        <path className="init-geometry-link" d="M205 187 315 245 M518 267 626 344 M330 378 251 459" />
        <circle className="init-geometry-anchor" cx="205" cy="187" r="4" />
        <circle className="init-geometry-anchor" cx="626" cy="344" r="4" />
        <circle className="init-geometry-anchor" cx="251" cy="459" r="4" />
        <Cube x={190} y={151} scale={0.35} delay={-0.8} />
        <Cube x={404} y={254} scale={1.02} accent />
        <Cube x={636} y={353} scale={0.47} delay={-1.7} />
        <Cube x={218} y={467} scale={0.29} delay={-2.4} />
        <path className="init-geometry-cross" d="M380 43v15m-7-7h14M694 510v15m-7-7h14M78 330v15m-7-7h14" />
      </svg>
      <div className="init-stage-visual-bottom"><span>LOCAL RUNTIME</span><span>●</span><span>SLOPPY</span></div>
    </div>
  );
}

export function InitStage({ children, state = "loading" }: InitStageProps) {
  return (
    <main className={`onboarding-loading-shell onboarding-loading-shell--init init-stage-shell init-stage-shell--${state}`}>
      <div className="init-stage-layout">
        <div className="init-stage-panel">
          <div className="init-stage-brand">
            <img src="/so_logo.svg" alt="" aria-hidden="true" />
            <span>Sloppy</span>
            <span className="init-stage-brand-divider" />
            <span className="init-stage-brand-section">Init</span>
          </div>
          {children}
          <div className="init-stage-panel-footer"><span>LOCAL DASHBOARD</span><span>SL / 01</span></div>
        </div>
        <InitGeometry state={state} />
      </div>
    </main>
  );
}
