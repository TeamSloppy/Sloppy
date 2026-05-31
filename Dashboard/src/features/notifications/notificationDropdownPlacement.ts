interface NotificationDropdownPlacementInput {
  triggerLeft: number;
  triggerRight: number;
  triggerBottom: number;
  dropdownWidth: number;
  viewportWidth: number;
  viewportHeight: number;
}

interface NotificationDropdownPlacement {
  left: number;
  bottom: number;
}

const DROPDOWN_GAP = 8;
const VIEWPORT_MARGIN = 12;

export function getNotificationDropdownPlacement({
  triggerLeft,
  triggerRight,
  triggerBottom,
  dropdownWidth,
  viewportWidth,
  viewportHeight
}: NotificationDropdownPlacementInput): NotificationDropdownPlacement {
  const preferredLeft = triggerRight + DROPDOWN_GAP;
  const maxLeft = Math.max(VIEWPORT_MARGIN, viewportWidth - dropdownWidth - VIEWPORT_MARGIN);
  const anchoredLeft = Math.min(Math.max(preferredLeft, VIEWPORT_MARGIN), maxLeft);

  return {
    left: preferredLeft <= maxLeft ? anchoredLeft : maxLeft,
    bottom: Math.max(0, viewportHeight - triggerBottom)
  };
}
