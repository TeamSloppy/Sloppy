import React from "react";
import "./GlitchText.css";

interface GlitchTextProps {
    text: string;
    className?: string;
    style?: React.CSSProperties;
}

export function GlitchText({ text, className = "", style }: GlitchTextProps) {
    return (
        <div className={`glitch-wrapper ${className}`} style={style}>
            <div className="glitch-text" title={text}>
                {text}
            </div>
        </div>
    );
}
