export interface UIOption {
  label: string;
  value: string;
}
export interface UIComponent {
  id: string;
  component: string;
  text?: string;
  children?: string[];
  label?: string;
  binding?: string;
  inputType?: string;
  required?: boolean;
  minimum?: number;
  maximum?: number;
  options?: UIOption[];
  action?: string;
}
export interface UISurface {
  protocolVersion: string;
  catalogId: string;
  surfaceId: string;
  revision: number;
  fallbackText: string;
  components: UIComponent[];
  dataModel?: unknown;
  isDeleted?: boolean;
  submittedActionId?: string;
}
export interface UIDraft {
  values: Record<string, unknown>;
  defaults: Record<string, unknown>;
  revision: number;
  pending?: any;
}
const kinds = new Set([
  "Text",
  "Column",
  "Row",
  "TextField",
  "CheckBox",
  "ChoicePicker",
  "Button",
]);
export function validSurface(value: any): value is UISurface {
  if (
    !value ||
    value.protocolVersion !== "0.9.1" ||
    value.catalogId !== "urn:sloppy:a2ui:catalog:v1" ||
    typeof value.surfaceId !== "string" ||
    !Number.isSafeInteger(value.revision) ||
    value.revision < 1 ||
    value.isDeleted ||
    !Array.isArray(value.components) ||
    value.components.length > 128
  )
    return false;
  const byId = new Map<string, UIComponent>();
  for (const item of value.components) {
    if (
      !item ||
      typeof item.id !== "string" ||
      !kinds.has(item.component) ||
      byId.has(item.id)
    )
      return false;
    if (
      ["Column", "Row"].includes(item.component) &&
      !Array.isArray(item.children)
    )
      return false;
    if (
      item.binding !== undefined &&
      (typeof item.binding !== "string" || !item.binding.startsWith("/"))
    )
      return false;
    byId.set(item.id, item);
  }
  const seen = new Set<string>();
  function visit(id: string, depth: number): boolean {
    const item = byId.get(id);
    if (!item || depth > 16 || seen.has(id)) return false;
    seen.add(id);
    return (item.children || []).every((child) => visit(child, depth + 1));
  }
  return visit("root", 1) && seen.size === byId.size;
}
export function initialValues(surface: UISurface): Record<string, unknown> {
  return Object.fromEntries(
    surface.components
      .filter((c) => c.binding)
      .map((c) => {
        let value: any = surface.dataModel;
        for (const token of (c.binding || "").slice(1).split("/")) {
          const key = token.replace(/~1/g, "/").replace(/~0/g, "~");
          value =
            value !== null &&
            typeof value === "object" &&
            Object.prototype.hasOwnProperty.call(value, key)
              ? value[key]
              : undefined;
        }
        return [
          c.binding!,
          value ??
            (c.component === "CheckBox"
              ? false
              : c.component === "TextField" && c.inputType !== "number"
                ? ""
                : null),
        ];
      }),
  );
}
export function reconcileDraft(
  surface: UISurface,
  previous?: UIDraft,
): UIDraft {
  const defaults = initialValues(surface);
  const values = { ...defaults };
  if (previous && !surface.submittedActionId)
    for (const key of Object.keys(defaults)) {
      if (
        Object.prototype.hasOwnProperty.call(previous.values, key) &&
        JSON.stringify(previous.values[key]) !==
          JSON.stringify(previous.defaults[key])
      )
        values[key] = previous.values[key];
    }
  return {
    defaults,
    values,
    revision: surface.revision,
    pending:
      !surface.submittedActionId && previous?.revision === surface.revision
        ? previous.pending
        : undefined,
  };
}
export function normalizedValues(
  surface: UISurface,
  raw: Record<string, unknown>,
): Record<string, unknown> {
  const values = { ...raw };
  for (const field of surface.components.filter(
    (c) => c.inputType === "number" && c.binding,
  )) {
    const value = values[field.binding!];
    if (typeof value === "string")
      values[field.binding!] = !value.trim()
        ? null
        : Number.isFinite(Number(value))
          ? Number(value)
          : value;
  }
  return values;
}
export function validationErrors(
  surface: UISurface,
  raw: Record<string, unknown>,
): Record<string, string> {
  const values = normalizedValues(surface, raw);
  const errors: Record<string, string> = {};
  for (const field of surface.components.filter((c) => c.binding)) {
    const path = field.binding!;
    const value = values[path];
    if ((value === null || value === undefined) && !field.required) continue;
    let valid = false;
    if (field.component === "TextField")
      valid =
        field.inputType === "number"
          ? typeof value === "number" &&
            Number.isFinite(value) &&
            (field.minimum === undefined || value >= field.minimum) &&
            (field.maximum === undefined || value <= field.maximum)
          : typeof value === "string" &&
            new TextEncoder().encode(value).length <= 16384 &&
            (!field.required || !!value.trim());
    if (field.component === "CheckBox")
      valid = typeof value === "boolean" && (!field.required || value === true);
    if (field.component === "ChoicePicker")
      valid = !!field.options?.some((option) => option.value === value);
    if (!valid) errors[path] = `Check ${field.label || path}`;
  }
  return errors;
}
