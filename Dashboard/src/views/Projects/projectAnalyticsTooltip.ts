const ANALYTICS_TOOLTIP_TEXT_COLOR = "var(--text, #e2e8f0)";

export function analyticsTooltipContentStyle() {
  return {
    backgroundColor: "var(--surface-2, #1e293b)",
    border: "1px solid var(--line-strong, #334155)",
    borderRadius: 0,
    fontSize: "0.76rem",
    color: ANALYTICS_TOOLTIP_TEXT_COLOR
  };
}

export function analyticsTooltipTextStyle() {
  return {
    color: ANALYTICS_TOOLTIP_TEXT_COLOR
  };
}
