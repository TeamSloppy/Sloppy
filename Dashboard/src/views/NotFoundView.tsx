import React from "react";
import { GlitchText } from "../components/GlitchText/GlitchText";

export function NotFoundView() {
    return (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', width: '100%', background: 'var(--bg-main)' }}>
            <GlitchText text="404" />
            <div style={{ marginTop: '20px', fontFamily: 'monospace', color: 'var(--text-secondary)' }}>PAGE_NOT_FOUND</div>
        </div>
    );
}
