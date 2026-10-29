# Sloppy A2UI profile

Call ui.catalog for the actual schemas. Envelopes use version "v0.9.1". One atomic batch targets one surface; always include a connected component named root. A new surface needs createSurface plus updateComponents in the same call. Updates merge components by id; to remove old nodes use deleteSurface/createSurface in one batch. The host data model is separate from the component tree.

Text has text; Row/Column have children IDs. TextField has label, binding, optional inputType (text or number), required, minimum, maximum. CheckBox has label, binding and optional required. ChoicePicker has label, binding, options [{label,value}] and optional required. Button has label and a symbolic action string. Bindings are absolute non-root JSON Pointers and must be unique. Numeric fields use JSON numbers, checkboxes booleans, choices declared strings. Button actions only send values to the agent.

## Task brief

Pass this array as the JSON string in messages, expectedRevision: 0, fallbackText: "Set the task title and choose a platform, or answer in text."

```json
[
  {"version":"v0.9.1","createSurface":{"surfaceId":"task-brief","catalogId":"urn:sloppy:a2ui:catalog:v1"}},
  {"version":"v0.9.1","updateComponents":{"surfaceId":"task-brief","components":[
    {"id":"root","component":"Column","children":["heading","title","platform","send"]},
    {"id":"heading","component":"Text","text":"Task brief"},
    {"id":"title","component":"TextField","label":"Goal","binding":"/goal","required":true},
    {"id":"platform","component":"ChoicePicker","label":"Platform","binding":"/platform","required":true,"options":[{"label":"iOS","value":"ios"},{"label":"Web","value":"web"}]},
    {"id":"send","component":"Button","label":"Continue","action":"submit_brief"}
  ]}},
  {"version":"v0.9.1","updateDataModel":{"surfaceId":"task-brief","value":{"goal":"","platform":"ios"}}}
]
```

For comparing approaches, put the sourced trade-offs in Text components and use a ChoicePicker plus a Continue button. For editable parameters, combine number TextFields with minimum/maximum and CheckBox fields. Use ui.catalog(surfaceId) before revising an existing form; local input drafts belong to the client and must not be guessed.
