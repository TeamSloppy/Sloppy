export type WorkspaceElementKind = "sticky" | "text" | "shape" | "image" | "table" | "frame" | "widget";

export interface WorkspaceRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface WorkspaceElement {
  id: string;
  kind: WorkspaceElementKind;
  bounds: WorkspaceRect;
  rotation: number;
  zIndex: number;
  parentId?: string | null;
  groupId?: string | null;
  style: Record<string, unknown>;
  data: Record<string, unknown>;
  revision: number;
}

export interface WorkspaceConnection {
  id: string;
  sourceElementId: string;
  targetElementId: string;
  label?: string | null;
  style: Record<string, unknown>;
  revision: number;
}

export interface WorkspaceDocument {
  workspaceId: string;
  schemaVersion: number;
  revision: number;
  elements: WorkspaceElement[];
  connections: WorkspaceConnection[];
}

export interface WorkspaceRecord {
  id: string;
  title: string;
  description: string;
  cover?: string | null;
  ownerId: string;
  projectId?: string | null;
  revision: number;
  isArchived: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface WorkspaceOperation {
  kind:
    | "element.create"
    | "element.update"
    | "element.move"
    | "element.resize"
    | "element.group"
    | "element.ungroup"
    | "element.frame_assign"
    | "element.z_order"
    | "element.delete"
    | "element.connect"
    | "element.disconnect"
    | "connection.create"
    | "connection.update"
    | "connection.delete";
  element?: WorkspaceElement;
  connection?: WorkspaceConnection;
  targetId?: string;
}

export interface WorkspaceTransaction {
  id: string;
  workspaceId: string;
  revision: number;
  actor: { kind: "user" | "agent" | "system"; id: string; displayName?: string | null };
  operations: WorkspaceOperation[];
  inverseOperations: WorkspaceOperation[];
  summary?: string | null;
  createdAt: string;
}

export interface WorkspaceTemplate {
  id: string;
  title: string;
  description: string;
  category: string;
  visibility: "builtin" | "personal" | "team";
  document: WorkspaceDocument;
}

export function makeElement(kind: WorkspaceElementKind, index: number): WorkspaceElement {
  const size = kind === "table"
    ? { width: 360, height: 220 }
    : kind === "frame"
      ? { width: 520, height: 360 }
      : kind === "text"
        ? { width: 280, height: 120 }
        : { width: 220, height: 160 };
  const id = `el-${crypto.randomUUID()}`;
  const data: Record<string, unknown> = kind === "table"
    ? { columns: ["Column 1", "Column 2"], rows: [["", ""], ["", ""]] }
    : { text: kind === "sticky" ? "New idea" : kind === "frame" ? "Frame" : "New element" };
  return {
    id,
    kind,
    bounds: { x: 120 + (index % 6) * 36, y: 100 + (index % 6) * 36, ...size },
    rotation: 0,
    zIndex: index + 1,
    style: {},
    data,
    revision: 0
  };
}

export function applyOperations(document: WorkspaceDocument, operations: WorkspaceOperation[], revision?: number): WorkspaceDocument {
  const elements = new Map(document.elements.map((element) => [element.id, element]));
  const connections = new Map(document.connections.map((connection) => [connection.id, connection]));
  for (const operation of operations) {
    const elementUpserts: WorkspaceOperation["kind"][] = [
      "element.create",
      "element.update",
      "element.move",
      "element.resize",
      "element.group",
      "element.ungroup",
      "element.frame_assign",
      "element.z_order"
    ];
    if (elementUpserts.includes(operation.kind) && operation.element) {
      elements.set(operation.element.id, operation.element);
    } else if (operation.kind === "element.delete" && operation.targetId) {
      elements.delete(operation.targetId);
      for (const [id, connection] of connections) {
        if (connection.sourceElementId === operation.targetId || connection.targetElementId === operation.targetId) {
          connections.delete(id);
        }
      }
    } else if ((operation.kind === "connection.create" || operation.kind === "connection.update" || operation.kind === "element.connect") && operation.connection) {
      connections.set(operation.connection.id, operation.connection);
    } else if ((operation.kind === "connection.delete" || operation.kind === "element.disconnect") && operation.targetId) {
      connections.delete(operation.targetId);
    }
  }
  return {
    ...document,
    revision: revision ?? document.revision,
    elements: [...elements.values()],
    connections: [...connections.values()]
  };
}
