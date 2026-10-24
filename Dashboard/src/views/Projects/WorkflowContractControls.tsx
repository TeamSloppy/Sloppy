import React, { useEffect, useState } from "react";

type RecordValue = Record<string, any>;
interface JSONFieldProps {
  label: string;
  value: unknown;
  onChange: (value: unknown) => void;
  onError: (message: string) => void;
}

function WorkflowJSONField({ label, value, onChange, onError }: JSONFieldProps) {
  const display = (value: unknown) => value === undefined ? "" : JSON.stringify(value, null, 2);
  const [text, setText] = useState(display(value));
  useEffect(() => {
    try { if (JSON.stringify(text ? JSON.parse(text) : undefined) === JSON.stringify(value)) return; } catch {}
    setText(display(value));
  }, [value]);
  return <label>{label}<textarea rows={5} value={text} onChange={(event) => {
    const next = event.target.value;
    setText(next);
    try {
      const parsed = next.trim() ? JSON.parse(next) : undefined;
      onChange(parsed);
      onError("");
    } catch { onError(`${label}: enter valid JSON before saving or running.`); }
  }} /></label>;
}

export function WorkflowOutputControls({ node, onChange, onError }: {
  node: RecordValue;
  onChange: (key: string, value: unknown) => void;
  onError: (message: string) => void;
}) {
  return <>
    {node.type === "agent_step" ? <label>Agent output<div className="project-workflow-choice-grid">
      {["text", "json"].map((format) => <button type="button" key={format} aria-label={format === "json" ? "JSON result" : "Text output"}
        className={(node.config?.outputFormat || "text") === format ? "active" : ""}
        onClick={() => onChange("outputFormat", format)}>{format === "json" ? "JSON result" : "Text"}</button>)}
    </div><small>JSON is stored in output.result. Invalid JSON stops the step.</small></label> : null}
    <WorkflowJSONField label="Step output schema (optional JSON)" value={node.config?.outputSchema}
      onChange={(value) => onChange("outputSchema", value)} onError={onError} />
    <small>Supported: type, properties, required, items, enum, minLength, additionalProperties. The root describes the output object.</small>
  </>;
}

export function WorkflowTransitionControls({ edge, onChange, onError }: {
  edge: RecordValue;
  onChange: (patch: RecordValue) => void;
  onError: (message: string) => void;
}) {
  const mode = edge.condition ? "value" : edge.conditionKey ? "key" : "default";
  return <>
    <label>Transition rule<div className="project-workflow-choice-grid">
      {["default", "key", "value"].map((choice) => <button key={choice} type="button" aria-label={choice === "value" ? "Output value" : choice === "key" ? "Legacy key" : "Default transition"} className={mode === choice ? "active" : ""} onClick={() => {
        onChange({ conditionKey: choice === "key" ? "approved" : "", condition: choice === "value" ? { path: "result.verdict", equals: "approved" } : undefined });
        onError("");
      }}>{choice === "value" ? "Output value" : choice === "key" ? "Legacy key" : "Default"}</button>)}
    </div></label>
    {mode === "key" ? <label>Condition key<input value={edge.conditionKey || ""} onChange={(event) => onChange({ conditionKey: event.target.value })} /></label> : null}
    {mode === "value" ? <>
      <label>Output path<input value={edge.condition.path} onChange={(event) => onChange({ condition: { ...edge.condition, path: event.target.value } })} placeholder="result.verdict" /></label>
      <WorkflowJSONField label="Equals (JSON value)" value={edge.condition.equals}
        onChange={(value) => onChange({ condition: { ...edge.condition, equals: value === undefined ? null : value } })} onError={onError} />
      <small>Values keep their types: false, 0 and "0" are different.</small>
    </> : null}
  </>;
}
