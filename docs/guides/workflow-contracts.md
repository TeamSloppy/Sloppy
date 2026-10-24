# Workflow output contracts

Runs use their pinned definition, including contracts and session policy. Existing graphs
default to text answers and a new agent session for each step.

## Outputs

An optional `config.outputSchema` validates the complete persisted step output before a
transition is selected, including continuation after human or agent input. Failed validation
retains the output for inspection and fails that attempt without starting downstream work.

Supported schema keywords: `type`, `properties`, `required`, `items`, `enum`, `minLength`,
`additionalProperties` (boolean), and `description`. Types are object, array, string,
number, integer, boolean and null. The root describes an object; nesting is limited to 16.
Unknown keywords are rejected. This is a deliberately bounded contract format, not a full
JSON Schema implementation. Required fields may be null only when their declared type allows null.

Agent steps with `config.outputFormat: "json"` must return exactly one JSON value. Markdown
fences or prose fail the step. The parsed value is stored in `output.result`; `output.text`
retains the original answer. User-controlled JSON cannot overwrite `agentId`, `sessionId`,
execution status or other envelope fields. The ordinary typed terminal outcome is still required.

```json
{
  "agentId": "developer",
  "prompt": "Return a verdict and a short explanation.",
  "outputFormat": "json",
  "outputSchema": {
    "type": "object",
    "required": ["result"],
    "properties": {
      "result": {
        "type": "object",
        "required": ["verdict"],
        "properties": {"verdict": {"type": "string", "enum": ["approved", "rejected"]}}
      }
    }
  }
}
```

Tool contracts describe their actual output fields, such as `stdout` or `exitCode`.
JSON mode is an agent setting; it does not imply parsing shell stdout.

## Transitions and references

An edge may use a legacy `conditionKey` or a typed condition, never both:

```json
{"id":"reviewed","sourceNodeId":"review","targetNodeId":"done","condition":{"path":"result.verdict","equals":"approved"}}
```

The path is relative to that node's output. Comparison preserves JSON types, so `false`,
`0`, and `"0"` differ. Missing typed fields and multiple matching edges fail the attempt.
An edge without either condition is the fallback; there can be only one per node.
Multiple edges do not launch parallel work. Drafts may remain unfinished, but a running
path must reach an explicit End node. Invalid updates leave the saved version unchanged.

Templates use `{{input.ticket}}` and `{{nodes.review.output.result.verdict}}`. Unknown nodes,
malformed placeholders and unavailable runtime fields are errors. Unexecuted branches
do not supply an output. Array elements can be addressed by index, such as `result.items.0`.
A whole-value template in tool arguments retains its JSON type; interpolation inside
text produces text. The `project.workflow` tool accepts `condition` as an object or JSON
object string, preserving boolean, null and numeric values.

The Dashboard exposes output format/schema and transition-rule controls. Invalid JSON
in these controls prevents Save and Run until corrected.
