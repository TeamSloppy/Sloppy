# Workflow API contract

Read this before composing a proposal. Checked against canonical implementation:
`Sources/Protocols/API/WorkflowAPIModels.swift` (DTOs/enums),
`Sources/sloppy/Tools/AgentTools/Project/WorkflowTool.swift` (tool schema/parser),
`Sources/sloppy/Workflows/{WorkflowRunner,WorkflowGraphContracts,WorkflowParallelTopology,WorkflowOutputContract}.swift`,
`Sources/sloppy/CoreService+Workflow{Agents,Sessions,Compact,Blocks,Control}.swift`,
`Sources/sloppy/Gateway/Routers/ProjectWorkflowsAPIRouter.swift`.
These are authoritative, not a generic workflow or JSON Schema standard. The companion
`contract-sources.sha256.json` is checked by `scripts/check-workflow-contract.py`;
source changes require reviewing this reference and rebaselining the hashes. Tests
`workflowToolDocumentsExamplesThroughActualParserAndValidator` parse both examples
through the real tool parser and graph validator. Do not start a workflow to validate it.

## Obtain the current schema

Read the exposed `project.workflow` schema in the tool catalog (or `mcp.list_tools`
when the tool is exposed through MCP). In a checkout read WorkflowTool.parameters and
the DTOs above. A provider can flatten optional fields into an all-fields presentation;
that does NOT mean empty strings are equivalent to omission. HTTP and tool payloads
are different. Inspect source and installed runtime version separately. No workflow CLI
subcommand is currently registered by `sloppy project --help`.

## Tool operations

`operation` is propose/start/link_agent_step/status/list. `projectId` may be omitted
only when current project is bound. Select a real project/agent/task, never invent IDs.

* `propose`: name (default Agent Workflow), lanes, nodes, edges; optional workflowId
  updates that definition, omission creates a NEW definition. No run is started.
  rationale/taskId are not persisted in the definition. A definition is a draft in the
  sense of not having a run, not a distinct lifecycle status. enabled defaults true;
  it does not itself execute anything. `enabled` is accepted by parser but is not
  advertised in the tool schema; use HTTP if explicitly setting it.
* `start`: workflowId or name lookup (first case-insensitive match); optional taskId,
  startedBy, input JSON object string, environment JSON object string, idempotencyKey
  UUID. Tool adds current sessionId to input if absent and forces background execution.
  Do NOT use this to test draft saving. A run pins definition version and inputs.
* `status`: runId returns run link; workflowId/name returns definition link. Without
  these, lists definitions. `list` uses the same resolution logic; omit selectors to
  actually list. Tool status does not return full graph: use HTTP GET to reread it.
* `link_agent_step`: workflowId/nodeId; agentId/sessionId/delegatedTaskId/agentStatus
  patch saved config. This is legacy linking metadata, NOT an executable session policy.
  In particular raw config.sessionId is rejected by the executor. Prefer sessionMode.

Optional top-level trimmed identifiers: omit/null/empty/whitespace mean absent. This
rule is NOT universal for nested fields. Unknown keys may be ignored, not validated.

## Proposal wire shapes

Tool lanes: required string id/title/kind; kind system/human/agent/team. Optional
actorId/teamId strings (metadata, not agent execution routing).
Tool nodes: required string id/type/title/laneId; config is an object encoded as a
JSON STRING in the advertised schema; the parser also accepts an object. Omitted or
empty-string config -> {}; null config is rejected. positionX/Y are optional numbers
(default 0; wrong types currently fall back to 0; send numeric 0, not false).
Tool edges: required string id/sourceNodeId/targetNodeId. Optional sourceSocket and
targetSocket strings top/right/bottom/left (presentation metadata).

`condition` omitted or null -> unconditional. Present value must be an object or JSON
object string containing string path and PRESENT equals (equals:null is valid).
`condition:""`, `condition:"{}"`, `{}`, malformed JSON, array, boolean or a missing
equals is INVALID. `conditionKey` omitted or null -> absent; `conditionKey:""` is
INVALID graph data, not a fallback. Never supply both condition and conditionKey.
When all-fields tooling cannot omit optional strings, use HTTP DTOs rather than fake
empty conditions. Do not silently weaken validation to accept them.

HTTP definition POST/PUT body is WorkflowDefinitionUpsertRequest:
required name:string, lanes:array, nodes:array, edges:array, enabled:boolean. No operation
or projectId in the body (projectId is in path). HTTP node requires config OBJECT,
positionX:number and positionY:number, even though Swift init has defaults: synthesized
Decodable does not apply initializer defaults. Optional lane/edge properties may be
omitted/null; mandatory arrays/strings/booleans/objects cannot be null. Typed condition
is an OBJECT, not a string. Use `{}` for empty node config. Optional equals may itself
be JSON null but the equals KEY must be present. IDs are stable within their category;
use simple nonempty strings. Node type is one of trigger, project_task, agent_step,
human_approval, human_input, tool_check, condition, parallel, join, update_task, notify, end.

## Graph validation vs execution

Exactly one trigger; unique lane/node/edge IDs; every node lane and edge endpoint must
exist. End cannot have outgoing edges. At most one unconditional fallback per ordinary
node. Duplicate legacy conditions, malformed typed paths, invalid session sources and
output schemas are graph errors. Draft validation currently permits unfinished graphs,
unreachable nodes, and absent agent prompts. Do not misreport those as statically
rejected. Before saving a runnable plan, independently check reachability from trigger,
all successful paths reaching End, no accidental cycles and executable configs. Runtime
fails explicit missing/ambiguous transitions; it never guesses a route. Each node has
at most 25 durable attempts. Loop uses maxIterations 1..24 (default 10).

## Executable node config and bindings

* trigger: `{}`; optional executionEnvironment object supplies run defaults.
* project_task: snapshots the RUN-bound task. config.taskId does not rebind a run.
  Start with real taskId; task.title/task.description and input.task.id are available.
* agent_step: required nonempty agentId and prompt at execution. sessionMode defaults
  new; explicitly choose new/shared/compact. model, reasoningEffort, mode use ordinary
  agent settings. Shared requires earlier agent-step sessionSourceNodeId, same agent,
  completed/idle source and same run/project/task scope. Compact summarizes selected
  completed source turn into fresh session (target agent may differ); bounded latest
  64000 input characters, 32000 summary characters. No raw sessionId. Source, boundary,
  compact summary/working sessions are checkpointed. Missing source does not fall back.
  Config taskId is NOT a per-step binding: use actual IDs in prompts/read full tasks.
  Run binding stays the root task. Output includes agentId/sessionId/text/agentOutcome;
  native waiting/error is not success. json outputFormat adds parsed output.result;
  text preserves original answer. ai_transform uses blockKind on agent_step.
* human_approval/human_input: prompt; pending action exposes approved/rejected/
  changes_requested decisions. Human Input requires nonempty response comment. Route
  approved explicitly and rejected/changes_requested to a non-success End, not execution.
* parallel: joinNodeId required. join: strategy all (default) or first_completed.
* condition: optional expression; expression/loop blockKind use bounded expressions,
  not JS eval. Merge is condition with blockKind merge and explicit Parallel ownership.
* tool_check: tool-specific config; registered tool uses tool/arguments, Bash uses
  blockKind bash + command; code uses blockKind code + language javascript/python + code;
  HTTP uses blockKind http + url/method/headers/body. Read executor before selecting
  tool config; permissions/approvals still apply. sub_workflow uses blockKind
  sub_workflow + workflowId and optional input object, pins child, rejects recursion
  and depth above eight. Do not retry unknown child effects as new children.
* update_task: status; updates RUN-bound task, requires taskId at start.
* notify: project channelId/message; only confirmed plugin delivery succeeds.
* end: {} means completed; optional status completed/failed/cancelled.

Templates `{{input.key}}`, `{{task.description}}`, `{{nodes.id.output.text}}` resolve
against pinned input/outputs. Unknown node refs fail graph validation; missing runtime
fields fail execution. Whole-value tool templates retain JSON type; text interpolation
produces text. Siblings have no outputs before Join. outputSchema validates ENTIRE
output object, not just text/result. Supported: type/properties/required/items/enum/
minLength/boolean additionalProperties/description, nesting <=16. Unsupported keywords
fail. Keep metadata envelope open; close result subtree if needed. Strict agent JSON
is stored at result, never allowed to overwrite execution metadata.

Typed branch path is relative to source output, e.g. result.verdict or decision.
Equals uses strict JSON equality; false/0/"0" differ. A missing field fails even if a
fallback exists; multiple matches fail. Legacy conditionKey matches true flags, boolean
result true/false, or string conditionKey/decision/status/result. Use a single fallback.

Parallel requires 2..16 distinct UNCONDITIONAL branch starts, disjoint until owned Join.
No external branch incoming edges, nested groups, or End before Join. Every branch node
must route to Join. Shared sessions must originate in the same branch. All branches
share pinned working directory: disjoint file ownership must be designed, not assumed.
Join all exposes final branch outputs under branches.<branchStartId>; first_completed
selects a successful winner and cancels others, not rollback. Failed branch stops group.

## HTTP lifecycle and safe recovery

Base `/v1/projects/:projectId`. GET/POST /workflows; GET/PUT/DELETE
/workflows/:workflowId. POST /workflows/:workflowId/runs starts with required startedBy
and input object; optional taskId/background/environment/idempotencyKey. GET
/workflow-runs, /workflow-runs/:runId, /workflow-actions. POST
/workflow-actions/:actionId/resolve (decision/resolvedBy/comment/background),
/workflow-runs/:runId/retry (stepId/decision/evidence/userId and accept_result output),
/workflow-runs/:runId/cancel (userId). Read WorkflowRunControl.swift for exact retry DTO.
Environment mode project/task_worktree/existing_worktree(path)/new_worktree(baseRef);
optional setupCommand. Setup may have effects; never run it to validate draft. Missing
pinned environment/checkpoint blocks, not fallback. New worktrees retained, never merged.

Schema parse errors are invalid_arguments with fieldPath/reason/hint from tool;
graph errors validation_failed with validationIssues. Permission denial is transport/
policy/service failure, not malformed JSON. HTTP keeps existing error codes and adds
schema/graph details where implemented. Never echo raw configs/prompts/secrets in errors.
Do not retry identical nonretryable calls. After uncertain create/update response, LIST
and GET to reconcile BEFORE any mutation. Draft creation has no idempotency key.
Start UUID key deduplicates identical requests, not different inputs. Retry requires
explicit evidence and inspection of completed effects. accept_result validates pinned
contract and actual native/child completion; uncertain shell result must show exitCode 0.
Cancel stops owned work/pending questions but does not undo effects. A saved draft is
not an executed run, and passing source tests does not upgrade an old live runtime.

Incident 2026-10-29: recorded propose payload had edges[0].condition == "". Parser
workflowConfig returned {}, then workflowEdges required path/equals and threw before
service/graph validation. The blanket catch discarded the location. In that SAME
payload conditionKey == "" is a second, graph-level error; changing only condition is
insufficient. positionX:false defaults to 0 and was not this parse failure. Tests cover
empty/malformed/missing-equals conditions, null condition, empty legacy key, invalid
node refs and both complete examples. No old tasks may be recreated during recovery.
