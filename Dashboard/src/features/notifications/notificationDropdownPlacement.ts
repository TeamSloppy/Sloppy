interface NotificationDropdownPlacementInput {
  triggerLeft: number;
  triggerRight: number;
  triggerTop: number;
  triggerBottom: number;
  dropdownWidth: number;
  dropdownHeight: number;
  viewportWidth: number;
  viewportHeight: number;
}

interface NotificationDropdownPlacement {
  left: number;
  top: number;
}

const DROPDOWN_GAP = 8;
const VIEWPORT_MARGIN = 12;

export function getNotificationDropdownPlacement({
  triggerLeft,
  triggerRight,
  triggerTop,
  triggerBottom,
  dropdownWidth,
  dropdownHeight,
  viewportWidth,
  viewportHeight
}: NotificationDropdownPlacementInput): NotificationDropdownPlacement {
  const preferredLeft = triggerRight + DROPDOWN_GAP;
  const maxLeft = Math.max(VIEWPORT_MARGIN, viewportWidth - dropdownWidth - VIEWPORT_MARGIN);
  const anchoredLeft = Math.min(Math.max(preferredLeft, VIEWPORT_MARGIN), maxLeft);

  const below = triggerBottom + DROPDOWN_GAP;
  const above = triggerTop - dropdownHeight - DROPDOWN_GAP;
  const preferredTop = below + dropdownHeight + VIEWPORT_MARGIN <= viewportHeight ? below : above;
  const maxTop = Math.max(VIEWPORT_MARGIN, viewportHeight - dropdownHeight - VIEWPORT_MARGIN);

  return {
    left: preferredLeft <= maxLeft ? anchoredLeft : maxLeft,
    top: Math.min(Math.max(preferredTop, VIEWPORT_MARGIN), maxTop)
  };
}
