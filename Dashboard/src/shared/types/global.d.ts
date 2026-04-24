declare global {
  interface SloppyClientConfig {
    apiBase?: string;
    accentColor?: string;
  }

  interface Window {
    __SLOPPY_CONFIG__?: SloppyClientConfig;
    Terminal?: new (options?: Record<string, unknown>) => {
      cols: number;
      rows: number;
      open: (element: HTMLElement) => void;
      focus: () => void;
      write: (data: string) => void;
      writeln: (data: string) => void;
      clear: () => void;
      dispose: () => void;
      loadAddon: (addon: { fit?: () => void }) => void;
      onData: (handler: (data: string) => void) => void;
      onResize: (handler: (size: { cols: number; rows: number }) => void) => void;
    };
    FitAddon?: new () => {
      fit: () => void;
    };
  }
}

export {};
