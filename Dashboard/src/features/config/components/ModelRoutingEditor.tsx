import React from "react";
import { AggregatedModelPicker } from "./AggregatedModelPicker";

export function ModelRoutingEditor({
  draftConfig,
  mutateDraft,
  modelRoutingCatalog,
  modelRoutingCatalogStatus
}) {
  const routing = draftConfig.modelRouting || {};
  const fast = routing.fast ?? "";
  const heavy = routing.heavy ?? "";

  return (
    <section className="entry-editor-card">
      <h3>Model aliases</h3>
      <p className="placeholder-text">
        Optional shortcuts for <code>model:</code> in skill <code>SKILL.md</code> frontmatter and for{" "}
        <code>workers.spawn</code> with <code>skillId</code>. Pick a model from your configured providers (same
        catalog as agent default model). Clear removes the alias.
      </p>
      {modelRoutingCatalogStatus ? (
        <p className="placeholder-text" style={{ marginBottom: 12 }}>
          {modelRoutingCatalogStatus}
        </p>
      ) : null}
      <div className="entry-form-grid" style={{ maxWidth: 640 }}>
        <AggregatedModelPicker
          label={
            <>
              Alias <code>fast</code> → model
            </>
          }
          value={fast}
          onChange={(id) =>
            mutateDraft((draft) => {
              if (!draft.modelRouting) draft.modelRouting = {};
              const v = String(id || "").trim();
              if (!v) {
                delete draft.modelRouting.fast;
              } else {
                draft.modelRouting.fast = v;
              }
            })
          }
          aggregatedModels={modelRoutingCatalog}
        />
        <AggregatedModelPicker
          label={
            <>
              Alias <code>heavy</code> → model
            </>
          }
          value={heavy}
          onChange={(id) =>
            mutateDraft((draft) => {
              if (!draft.modelRouting) draft.modelRouting = {};
              const v = String(id || "").trim();
              if (!v) {
                delete draft.modelRouting.heavy;
              } else {
                draft.modelRouting.heavy = v;
              }
            })
          }
          aggregatedModels={modelRoutingCatalog}
        />
      </div>
      <p className="placeholder-text" style={{ marginTop: 12 }}>
        Advanced: add more keys by editing the JSON in the <strong>Config</strong> raw view — <code>modelRouting</code>{" "}
        is a flat string map.
      </p>
    </section>
  );
}
