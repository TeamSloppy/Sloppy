export interface DashboardFeatureFlags {
  sidebarProjectChats: boolean;
}

// Runtime /config.json flags are opt-in so missing config keeps the sidebar quiet.
export function resolveDashboardFeatureFlags(config: SloppyClientConfig | undefined): DashboardFeatureFlags {
  return {
    sidebarProjectChats: config?.features?.sidebarProjectChats === true
  };
}
