import React from "react";
import { GlitchText } from "../components/GlitchText/GlitchText";

interface ErrorViewProps {
    error?: Error;
    resetErrorBoundary?: () => void;
}

export function ErrorView({ error, resetErrorBoundary }: ErrorViewProps) {
    return (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', width: '100%', background: 'var(--bg-main)', position: 'relative' }}>
            <GlitchText text="ERROR" className="error-glitch" style={{ color: 'var(--danger)', fontSize: '72px' }} />
            <div style={{ marginTop: '20px', fontFamily: 'monospace', color: 'var(--text-secondary)', textAlign: 'center', maxWidth: '600px', padding: '0 20px' }}>
                <div style={{ marginBottom: '10px' }}>SYSTEM_FAILURE_DETECTED</div>
                {error && (
                    <div style={{ background: 'rgba(0,0,0,0.5)', padding: '10px', borderRadius: '4px', border: '1px solid var(--danger)', color: 'var(--danger)', fontSize: '12px', textAlign: 'left', overflow: 'auto', maxHeight: '200px' }}>
                        {error.message}
                    </div>
                )}
                {resetErrorBoundary && (
                    <button
                        onClick={resetErrorBoundary}
                        style={{ marginTop: '20px', padding: '8px 16px', background: 'transparent', border: '1px solid var(--accent)', color: 'var(--accent)', cursor: 'pointer', fontFamily: 'monospace' }}
                    >
                        [ REBOOT_SYSTEM ]
                    </button>
                )}
            </div>
        </div>
    );
}
