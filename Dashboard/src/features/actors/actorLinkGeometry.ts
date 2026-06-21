export const NODE_WIDTH = 180;
export const NODE_HEIGHT = 88;

export const SOCKETS = ["top", "right", "bottom", "left"];
export const RELATIONSHIPS = ["hierarchical", "peer"];

const PARALLEL_LINK_SPACING = 18;

export function normalizeSocket(value, fallback = "right") {
  const socket = String(value ?? fallback).trim() || fallback;
  return SOCKETS.includes(socket) ? socket : fallback;
}

export function inferRelationshipFromSockets(sourceSocket, targetSocket) {
  if (
    (sourceSocket === "bottom" && targetSocket === "top")
    || (sourceSocket === "top" && targetSocket === "bottom")
  ) {
    return "hierarchical";
  }
  return "peer";
}

export function socketPoint(node, socket) {
  switch (socket) {
    case "top":
      return { x: node.positionX + NODE_WIDTH / 2, y: node.positionY };
    case "right":
      return { x: node.positionX + NODE_WIDTH, y: node.positionY + NODE_HEIGHT / 2 };
    case "bottom":
      return { x: node.positionX + NODE_WIDTH / 2, y: node.positionY + NODE_HEIGHT };
    case "left":
    default:
      return { x: node.positionX, y: node.positionY + NODE_HEIGHT / 2 };
  }
}

function socketTangent(socket) {
  switch (socket) {
    case "top":
      return { x: 0, y: -1 };
    case "right":
      return { x: 1, y: 0 };
    case "bottom":
      return { x: 0, y: 1 };
    case "left":
    default:
      return { x: -1, y: 0 };
  }
}

export function oppositeSocket(socket) {
  switch (socket) {
    case "top":
      return "bottom";
    case "right":
      return "left";
    case "bottom":
      return "top";
    case "left":
    default:
      return "right";
  }
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function offsetPoint(point, normal, offset) {
  return {
    x: point.x + normal.x * offset,
    y: point.y + normal.y * offset
  };
}

function linkNormal(source, target) {
  const dx = target.x - source.x;
  const dy = target.y - source.y;
  const length = Math.hypot(dx, dy);
  if (length === 0) {
    return { x: 0, y: -1 };
  }
  return { x: -dy / length, y: dx / length };
}

export function buildBezierPath(source, target, sourceSocket, targetSocket, offset = 0) {
  const sourceTangent = socketTangent(sourceSocket);
  const targetTangent = socketTangent(targetSocket);
  const dx = target.x - source.x;
  const dy = target.y - source.y;
  const distance = Math.hypot(dx, dy);
  const handle = clamp(distance * 0.35, 34, 140);
  const normal = linkNormal(source, target);
  const shiftedSource = offsetPoint(source, normal, offset);
  const shiftedTarget = offsetPoint(target, normal, offset);

  const c1 = offsetPoint({
    x: source.x + sourceTangent.x * handle,
    y: source.y + sourceTangent.y * handle
  }, normal, offset);
  const c2 = offsetPoint({
    x: target.x + targetTangent.x * handle,
    y: target.y + targetTangent.y * handle
  }, normal, offset);

  return `M ${shiftedSource.x} ${shiftedSource.y} C ${c1.x} ${c1.y}, ${c2.x} ${c2.y}, ${shiftedTarget.x} ${shiftedTarget.y}`;
}

function routeKey(link) {
  return [
    link.sourceActorId,
    link.targetActorId,
    normalizeSocket(link.sourceSocket, "right"),
    normalizeSocket(link.targetSocket, "left")
  ].join("\u0000");
}

function parallelOffset(index, total) {
  if (total <= 1) {
    return 0;
  }
  return (index - (total - 1) / 2) * PARALLEL_LINK_SPACING;
}

export function buildActorLinkRenderModels(links, nodeMap) {
  const groups = new Map();
  for (const link of links) {
    const key = routeKey(link);
    const group = groups.get(key) || [];
    group.push(link.id);
    groups.set(key, group);
  }

  return links.map((link) => {
    const sourceNode = nodeMap.get(link.sourceActorId);
    const targetNode = nodeMap.get(link.targetActorId);
    if (!sourceNode || !targetNode) {
      return null;
    }

    const sourceSocket = normalizeSocket(link.sourceSocket, "right");
    const targetSocket = normalizeSocket(link.targetSocket, "left");
    const source = socketPoint(sourceNode, sourceSocket);
    const target = socketPoint(targetNode, targetSocket);
    const siblings = groups.get(routeKey(link)) || [link.id];
    const offset = parallelOffset(siblings.indexOf(link.id), siblings.length);
    const normal = linkNormal(source, target);
    const relationship = link.relationship || inferRelationshipFromSockets(sourceSocket, targetSocket);
    const midX = (source.x + target.x) / 2 + normal.x * offset;
    const midY = (source.y + target.y) / 2 + normal.y * offset;

    return {
      link,
      source,
      target,
      sourceSocket,
      targetSocket,
      relationship,
      offset,
      path: buildBezierPath(source, target, sourceSocket, targetSocket, offset),
      reversePath: buildBezierPath(target, source, targetSocket, sourceSocket, -offset),
      midX,
      midY
    };
  }).filter(Boolean);
}
