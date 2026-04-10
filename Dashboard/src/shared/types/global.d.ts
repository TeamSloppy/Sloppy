declare global {
  interface SloppyClientConfig {
    apiBase?: string;
    accentColor?: string;
  }

  interface Window {
    __SLOPPY_CONFIG__?: SloppyClientConfig;
  }
}

export {};
