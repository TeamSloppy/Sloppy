import React, { useEffect, useMemo, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from "recharts";
import { fetchProjectAnalytics } from "../../api";

type WindowOption = "24h" | "7d" | "all";

const OUTCOME_COLORS: Record<string, string> = {
  success: "#5eead4",
  failed: "#f87171",
  interrupted: "#fcd34d"
};

const RUNTIME_BAR_COLOR = "var(--accent, #38bdf8)";
const TOOL_BAR_COLOR = "var(--accent-muted, #94a3b8)";

const TOKEN_PIE_COLORS: Record<string, string> = {
  prompt: "#818cf8",
  completion: "#c084fc"
};

function formatNumber(value: unknown) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "0";
  return n.toLocaleString("en-US");
}

function formatPercent(value: unknown) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "0%";
  return `${Math.round(n * 100)}%`;
}

function sortCounts(obj: any) {
  const entries = Object.entries(obj || {});
  entries.sort((a, b) => Number(b[1] || 0) - Number(a[1] || 0));
  return entries;
}

function analyticsTooltipStyle() {
  return {
    backgroundColor: "var(--surface-2, #1e293b)",
    border: "1px solid var(--line-strong, #334155)",
    borderRadius: 0,
    fontSize: "0.76rem",
    color: "var(--text, #e2e8f0)"
  };
}

export function ProjectAnalyticsTab({
  project,
  onOpenTab
}: {
  project: any;
  onOpenTab?: (tabId: string) => void;
}) {
  const projectId = String(project?.id || "").trim();
  const [timeWindow, setTimeWindow] = useState<WindowOption>("24h");
  const [response, setResponse] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (!projectId) return;
    let cancelled = false;

    async function load() {
      setIsLoading(true);
      const data = await fetchProjectAnalytics(projectId, { window: timeWindow }).catch(() => null);
      if (cancelled) return;
      setResponse(data);
      setIsLoading(false);
    }

    load();
    return () => {
      cancelled = true;
    };
  }, [projectId, timeWindow]);

  const runtimeCounts = response?.runtimeEventCounts || {};
  const toolStats = response?.tools || {};
  const taskOutcomes = response?.taskOutcomes || {};
  const tokenUsage = response?.tokenUsage || {};

  const topRuntime = useMemo(() => sortCounts(runtimeCounts).slice(0, 10), [runtimeCounts]);

  const outcomePieData = useMemo(() => {
    const s = taskOutcomes || {};
    return [
      { name: "Done", value: Number(s.success) || 0, key: "success" },
      { name: "Blocked", value: Number(s.failed) || 0, key: "failed" },
      { name: "Cancelled", value: Number(s.interrupted) || 0, key: "interrupted" }
    ].filter((d) => d.value > 0);
  }, [taskOutcomes]);

  const tokenPieData = useMemo(() => {
    const prompt = Number(tokenUsage?.totalPromptTokens) || 0;
    const completion = Number(tokenUsage?.totalCompletionTokens) || 0;
    return [
      { name: "Prompt", value: prompt, key: "prompt" },
      { name: "Completion", value: completion, key: "completion" }
    ].filter((d) => d.value > 0);
  }, [tokenUsage]);

  const runtimeBarData = useMemo(
    () =>
      topRuntime.map(([key, value]) => ({
        name: key.length > 40 ? `${key.slice(0, 38)}…` : key,
        fullName: key,
        value: Number(value) || 0
      })),
    [topRuntime]
  );

  const topToolsByTimeData = useMemo(() => {
    const list = toolStats?.topToolsByTime || [];
    return list.slice(0, 8).map((t: any) => ({
      name:
        String(t.tool || "").length > 32
          ? `${String(t.tool).slice(0, 30)}…`
          : String(t.tool || "—"),
      fullName: String(t.tool || ""),
      calls: Number(t.calls) || 0,
      failures: Number(t.failures) || 0,
      avgMs: t.avgDurationMs != null ? Number(t.avgDurationMs) : null
    }));
  }, [toolStats]);

  const topFailingToolsData = useMemo(() => {
    const list = toolStats?.topFailingTools || [];
    return list.slice(0, 8).map((t: any) => ({
      name:
        String(t.tool || "").length > 32
          ? `${String(t.tool).slice(0, 30)}…`
          : String(t.tool || "—"),
      fullName: String(t.tool || ""),
      failures: Number(t.failures) || 0,
      calls: Number(t.calls) || 0
    }));
  }, [toolStats]);

  return (
    <section className="project-tab-layout">
      <section className="project-pane">
        <div className="project-pane-head">
          <h4>Project Analytics</h4>
          <div className="project-analytics-window">
            <button
              type="button"
              className={`project-pane-link ${timeWindow === "24h" ? "active" : ""}`}
              onClick={() => setTimeWindow("24h")}
            >
              24h
            </button>
            <button
              type="button"
              className={`project-pane-link ${timeWindow === "7d" ? "active" : ""}`}
              onClick={() => setTimeWindow("7d")}
            >
              7d
            </button>
            <button
              type="button"
              className={`project-pane-link ${timeWindow === "all" ? "active" : ""}`}
              onClick={() => setTimeWindow("all")}
            >
              all
            </button>
          </div>
        </div>

        {isLoading ? (
          <p className="placeholder-text">Loading analytics…</p>
        ) : !response ? (
          <div className="project-overview-empty">
            <p className="placeholder-text">No analytics available yet.</p>
          </div>
        ) : (
          <div className="project-analytics-grid">
            <section className="project-analytics-card project-analytics-card--split">
              <div className="project-analytics-card-head">
                <strong>Task outcomes</strong>
                {onOpenTab ? (
                  <button type="button" className="project-pane-link" onClick={() => onOpenTab("tasks")}>
                    Open Tasks
                  </button>
                ) : null}
              </div>
              <div className="project-analytics-split">
                <div className="project-analytics-chart-wrap">
                  {outcomePieData.length === 0 ? (
                    <p className="placeholder-text project-analytics-chart-empty">No completed tasks in this window.</p>
                  ) : (
                    <ResponsiveContainer width="100%" height={300}>
                      <PieChart>
                        <Pie
                          data={outcomePieData}
                          dataKey="value"
                          nameKey="name"
                          cx="50%"
                          cy="50%"
                          innerRadius={56}
                          outerRadius={96}
                          paddingAngle={2}
                        >
                          {outcomePieData.map((entry) => (
                            <Cell
                              key={entry.key}
                              fill={OUTCOME_COLORS[entry.key] || "#94a3b8"}
                              stroke="var(--surface, #0f172a)"
                              strokeWidth={1}
                            />
                          ))}
                        </Pie>
                        <Tooltip
                          contentStyle={analyticsTooltipStyle()}
                          formatter={(value: number, _name: string, item: any) => [
                            formatNumber(value),
                            item?.payload?.name ?? ""
                          ]}
                        />
                      </PieChart>
                    </ResponsiveContainer>
                  )}
                </div>
                <div className="project-analytics-kv">
                  <div><span>Total</span><strong>{formatNumber(taskOutcomes.total)}</strong></div>
                  <div><span>Success (done)</span><strong>{formatNumber(taskOutcomes.success)}</strong></div>
                  <div><span>Failed (blocked)</span><strong>{formatNumber(taskOutcomes.failed)}</strong></div>
                  <div><span>Interrupted (cancelled)</span><strong>{formatNumber(taskOutcomes.interrupted)}</strong></div>
                </div>
              </div>
            </section>

            <section className="project-analytics-card">
              <div className="project-analytics-card-head">
                <strong>Tool tracing</strong>
              </div>
              <div className="project-analytics-kv project-analytics-kv--tools-summary">
                <div><span>Total calls</span><strong>{formatNumber(toolStats.totalCalls)}</strong></div>
                <div><span>Failures</span><strong>{formatNumber(toolStats.totalFailures)}</strong></div>
                <div><span>Failure rate</span><strong>{formatPercent(toolStats.failureRate)}</strong></div>
                <div><span>Avg duration</span><strong>{toolStats.avgDurationMs ? `${formatNumber(toolStats.avgDurationMs)} ms` : "—"}</strong></div>
                <div><span>P50</span><strong>{toolStats.p50DurationMs ? `${formatNumber(toolStats.p50DurationMs)} ms` : "—"}</strong></div>
                <div><span>P95</span><strong>{toolStats.p95DurationMs ? `${formatNumber(toolStats.p95DurationMs)} ms` : "—"}</strong></div>
              </div>
              {topToolsByTimeData.length > 0 ? (
                <div className="project-analytics-chart-block">
                  <span className="project-analytics-chart-label">Top tools by time</span>
                  <div className="project-analytics-chart-wrap project-analytics-chart-wrap--bar">
                    <ResponsiveContainer width="100%" height={Math.min(280, 36 + topToolsByTimeData.length * 28)}>
                      <BarChart layout="vertical" data={topToolsByTimeData} margin={{ top: 4, right: 12, left: 4, bottom: 4 }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="var(--line, #334155)" horizontal={false} />
                        <XAxis type="number" tick={{ fill: "var(--muted)", fontSize: 11 }} tickFormatter={(v) => formatNumber(v)} />
                        <YAxis
                          type="category"
                          dataKey="name"
                          width={120}
                          tick={{ fill: "var(--muted)", fontSize: 10 }}
                        />
                        <Tooltip
                          contentStyle={analyticsTooltipStyle()}
                          formatter={(value: number) => [formatNumber(value), "Calls"]}
                          labelFormatter={(_label, payload) =>
                            payload?.[0]?.payload?.fullName || _label
                          }
                        />
                        <Bar dataKey="calls" name="calls" fill={TOOL_BAR_COLOR} radius={[0, 2, 2, 0]} />
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                </div>
              ) : null}
              {topFailingToolsData.length > 0 ? (
                <div className="project-analytics-chart-block">
                  <span className="project-analytics-chart-label">Top failing tools</span>
                  <div className="project-analytics-chart-wrap project-analytics-chart-wrap--bar">
                    <ResponsiveContainer width="100%" height={Math.min(280, 36 + topFailingToolsData.length * 28)}>
                      <BarChart layout="vertical" data={topFailingToolsData} margin={{ top: 4, right: 12, left: 4, bottom: 4 }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="var(--line, #334155)" horizontal={false} />
                        <XAxis type="number" tick={{ fill: "var(--muted)", fontSize: 11 }} tickFormatter={(v) => formatNumber(v)} />
                        <YAxis
                          type="category"
                          dataKey="name"
                          width={120}
                          tick={{ fill: "var(--muted)", fontSize: 10 }}
                        />
                        <Tooltip
                          contentStyle={analyticsTooltipStyle()}
                          formatter={(value: number) => [formatNumber(value), "Failures"]}
                          labelFormatter={(_label, payload) =>
                            payload?.[0]?.payload?.fullName || _label
                          }
                        />
                        <Bar dataKey="failures" name="failures" fill="#f87171" radius={[0, 2, 2, 0]} />
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                </div>
              ) : null}
            </section>

            <section className="project-analytics-card project-analytics-card--wide">
              <div className="project-analytics-card-head">
                <strong>Runtime events</strong>
                <span className="placeholder-text">{Object.keys(runtimeCounts).length} types</span>
              </div>
              {topRuntime.length === 0 ? (
                <p className="placeholder-text">No tracked runtime events in this window.</p>
              ) : (
                <>
                  <div className="project-analytics-chart-wrap project-analytics-chart-wrap--bar">
                    <ResponsiveContainer width="100%" height={Math.min(360, 40 + runtimeBarData.length * 26)}>
                      <BarChart layout="vertical" data={runtimeBarData} margin={{ top: 4, right: 16, left: 8, bottom: 4 }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="var(--line, #334155)" horizontal={false} />
                        <XAxis type="number" tick={{ fill: "var(--muted)", fontSize: 11 }} tickFormatter={(v) => formatNumber(v)} />
                        <YAxis
                          type="category"
                          dataKey="name"
                          width={220}
                          tick={{ fill: "var(--muted)", fontSize: 10 }}
                        />
                        <Tooltip
                          contentStyle={analyticsTooltipStyle()}
                          formatter={(value: number) => [formatNumber(value), "Count"]}
                          labelFormatter={(_label, payload) =>
                            payload?.[0]?.payload?.fullName || _label
                          }
                        />
                        <Bar dataKey="value" name="count" fill={RUNTIME_BAR_COLOR} radius={[0, 2, 2, 0]} />
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                  <div className="project-analytics-list project-analytics-list--compact">
                    {topRuntime.map(([key, value]) => (
                      <div key={key} className="project-analytics-row">
                        <span className="project-analytics-row-key" title={key}>
                          {key}
                        </span>
                        <strong className="project-analytics-row-value">{formatNumber(value)}</strong>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </section>

            <section className="project-analytics-card project-analytics-card--split">
              <div className="project-analytics-card-head">
                <strong>Token usage</strong>
              </div>
              <div className="project-analytics-split">
                <div className="project-analytics-chart-wrap">
                  {tokenPieData.length === 0 ? (
                    <p className="placeholder-text project-analytics-chart-empty">No token usage in this window.</p>
                  ) : (
                    <ResponsiveContainer width="100%" height={280}>
                      <PieChart>
                        <Pie
                          data={tokenPieData}
                          dataKey="value"
                          nameKey="name"
                          cx="50%"
                          cy="50%"
                          innerRadius={48}
                          outerRadius={88}
                          paddingAngle={2}
                        >
                          {tokenPieData.map((entry) => (
                            <Cell
                              key={entry.key}
                              fill={TOKEN_PIE_COLORS[entry.key] || "#94a3b8"}
                              stroke="var(--surface, #0f172a)"
                              strokeWidth={1}
                            />
                          ))}
                        </Pie>
                        <Tooltip
                          contentStyle={analyticsTooltipStyle()}
                          formatter={(value: number, _name: string, item: any) => [
                            formatNumber(value),
                            item?.payload?.name ?? ""
                          ]}
                        />
                      </PieChart>
                    </ResponsiveContainer>
                  )}
                </div>
                <div className="project-analytics-kv">
                  <div><span>Prompt</span><strong>{formatNumber(tokenUsage.totalPromptTokens)}</strong></div>
                  <div><span>Completion</span><strong>{formatNumber(tokenUsage.totalCompletionTokens)}</strong></div>
                  <div><span>Total</span><strong>{formatNumber(tokenUsage.totalTokens)}</strong></div>
                </div>
              </div>
            </section>
          </div>
        )}
      </section>
    </section>
  );
}

