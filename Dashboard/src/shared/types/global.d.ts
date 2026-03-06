interface SloppyClientConfig {
  apiBase?: string;
  accentColor?: string;
}

declare global {
  interface Window {
    __SLOPPY_CONFIG__?: SloppyClientConfig;
  }
}

export {};
