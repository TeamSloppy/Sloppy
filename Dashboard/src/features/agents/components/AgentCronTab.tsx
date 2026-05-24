import React, { useEffect, useMemo, useState } from "react";
import {
    fetchAgentCronTasks,
    createAgentCronTask,
    updateAgentCronTask,
    deleteAgentCronTask,
    fetchActorsBoard,
    sendChannelMessage
} from "../../../api";

const WEEKDAYS = [
    { value: "1", label: "Mon" },
    { value: "2", label: "Tue" },
    { value: "3", label: "Wed" },
    { value: "4", label: "Thu" },
    { value: "5", label: "Fri" },
    { value: "6", label: "Sat" },
    { value: "0", label: "Sun" }
];

const SCHEDULE_MODES = [
    { value: "interval", label: "Minutes" },
    { value: "hourly", label: "Hours" },
    { value: "daily", label: "Daily" },
    { value: "weekly", label: "Weekly" },
    { value: "custom", label: "Cron" }
];

function clampNumber(value, fallback, min, max) {
    const parsed = Number.parseInt(String(value), 10);
    if (!Number.isFinite(parsed)) {
        return fallback;
    }
    return Math.min(max, Math.max(min, parsed));
}

function padNumber(value) {
    return String(value).padStart(2, "0");
}

function normalizeTime(value, fallback = "09:00") {
    const match = String(value || "").match(/^(\d{1,2}):(\d{1,2})$/);
    if (!match) {
        return fallback;
    }
    const hour = clampNumber(match[1], 9, 0, 23);
    const minute = clampNumber(match[2], 0, 0, 59);
    return `${padNumber(hour)}:${padNumber(minute)}`;
}

function timeParts(value, fallback = "09:00") {
    const normalized = normalizeTime(value, fallback);
    const [hour, minute] = normalized.split(":");
    return {
        hour: Number.parseInt(hour, 10),
        minute: Number.parseInt(minute, 10),
        label: normalized
    };
}

function defaultScheduleFields(schedule = "*/5 * * * *") {
    return {
        schedule,
        scheduleMode: "interval",
        intervalMinutes: "5",
        hourlyInterval: "1",
        hourlyMinute: "0",
        dailyTime: "09:00",
        weeklyDay: "1",
        weeklyTime: "09:00"
    };
}

function scheduleFieldsFromExpression(schedule) {
    const expression = String(schedule || "").trim() || "*/5 * * * *";
    const fallback = { ...defaultScheduleFields(expression), scheduleMode: "custom" };
    const parts = expression.split(/\s+/).filter(Boolean);
    if (parts.length !== 5) {
        return fallback;
    }

    const [minute, hour, day, month, weekday] = parts;
    const exactMinute = Number.parseInt(minute, 10);
    const exactHour = Number.parseInt(hour, 10);
    const minuteStep = minute === "*" ? 1 : minute.match(/^\*\/(\d+)$/);
    const hourStep = hour === "*" ? 1 : hour.match(/^\*\/(\d+)$/);

    if ((minuteStep === 1 || minuteStep) && hour === "*" && day === "*" && month === "*" && weekday === "*") {
        return {
            ...defaultScheduleFields(expression),
            scheduleMode: "interval",
            intervalMinutes: String(minuteStep === 1 ? 1 : clampNumber(minuteStep[1], 5, 1, 59))
        };
    }

    if (Number.isFinite(exactMinute) && (hourStep === 1 || hourStep) && day === "*" && month === "*" && weekday === "*") {
        return {
            ...defaultScheduleFields(expression),
            scheduleMode: "hourly",
            hourlyInterval: String(hourStep === 1 ? 1 : clampNumber(hourStep[1], 1, 1, 23)),
            hourlyMinute: String(clampNumber(exactMinute, 0, 0, 59))
        };
    }

    if (Number.isFinite(exactMinute) && Number.isFinite(exactHour) && day === "*" && month === "*" && weekday === "*") {
        return {
            ...defaultScheduleFields(expression),
            scheduleMode: "daily",
            dailyTime: `${padNumber(clampNumber(exactHour, 9, 0, 23))}:${padNumber(clampNumber(exactMinute, 0, 0, 59))}`
        };
    }

    if (Number.isFinite(exactMinute) && Number.isFinite(exactHour) && day === "*" && month === "*" && /^\d+$/.test(weekday)) {
        return {
            ...defaultScheduleFields(expression),
            scheduleMode: "weekly",
            weeklyDay: weekday === "7" ? "0" : weekday,
            weeklyTime: `${padNumber(clampNumber(exactHour, 9, 0, 23))}:${padNumber(clampNumber(exactMinute, 0, 0, 59))}`
        };
    }

    return fallback;
}

function buildScheduleExpression(form) {
    switch (form.scheduleMode) {
        case "interval": {
            const minutes = clampNumber(form.intervalMinutes, 5, 1, 59);
            return `*/${minutes} * * * *`;
        }
        case "hourly": {
            const hours = clampNumber(form.hourlyInterval, 1, 1, 23);
            const minute = clampNumber(form.hourlyMinute, 0, 0, 59);
            return `${minute} ${hours === 1 ? "*" : `*/${hours}`} * * *`;
        }
        case "daily": {
            const time = timeParts(form.dailyTime);
            return `${time.minute} ${time.hour} * * *`;
        }
        case "weekly": {
            const time = timeParts(form.weeklyTime);
            const weekday = WEEKDAYS.some((day) => day.value === String(form.weeklyDay)) ? form.weeklyDay : "1";
            return `${time.minute} ${time.hour} * * ${weekday}`;
        }
        case "custom":
        default:
            return String(form.schedule || "").trim();
    }
}

function plural(value, unit) {
    return `${value} ${unit}${value === 1 ? "" : "s"}`;
}

function describeSchedule(form) {
    switch (form.scheduleMode) {
        case "interval": {
            const minutes = clampNumber(form.intervalMinutes, 5, 1, 59);
            return `Every ${plural(minutes, "minute")}`;
        }
        case "hourly": {
            const hours = clampNumber(form.hourlyInterval, 1, 1, 23);
            const minute = clampNumber(form.hourlyMinute, 0, 0, 59);
            return `Every ${plural(hours, "hour")} at :${padNumber(minute)}`;
        }
        case "daily": {
            const time = timeParts(form.dailyTime);
            return `Every day at ${time.label}`;
        }
        case "weekly": {
            const time = timeParts(form.weeklyTime);
            const weekday = WEEKDAYS.find((day) => day.value === String(form.weeklyDay))?.label || "Mon";
            return `Every ${weekday} at ${time.label}`;
        }
        case "custom":
        default:
            return "Custom cron schedule";
    }
}

function describeCronExpression(schedule) {
    return describeSchedule(scheduleFieldsFromExpression(schedule));
}

function buildCronPayload(form) {
    return {
        schedule: buildScheduleExpression(form),
        command: form.command,
        channelId: form.channelId,
        enabled: form.enabled
    };
}

function cronTestContent(command, cronId = "draft") {
    return `CRON TRIGGER: ${String(command || "").trim()}

Cron metadata:
- source: cron_test
- cronTaskId: ${cronId}`;
}

function CronScheduleBuilder({ form, onFormChange }) {
    const expression = buildScheduleExpression(form);

    return (
        <div className="cron-schedule-builder">
            <div className="cron-schedule-modes" role="tablist" aria-label="Schedule type">
                {SCHEDULE_MODES.map((mode) => (
                    <button
                        key={mode.value}
                        type="button"
                        className={form.scheduleMode === mode.value ? "active" : ""}
                        onClick={() => onFormChange("scheduleMode", mode.value)}
                    >
                        {mode.label}
                    </button>
                ))}
            </div>

            {form.scheduleMode === "interval" ? (
                <div className="cron-schedule-row">
                    <span>Every</span>
                    <input
                        type="number"
                        min="1"
                        max="59"
                        value={form.intervalMinutes}
                        onChange={(event) => onFormChange("intervalMinutes", event.target.value)}
                    />
                    <span>minutes</span>
                </div>
            ) : null}

            {form.scheduleMode === "hourly" ? (
                <div className="cron-schedule-row">
                    <span>Every</span>
                    <input
                        type="number"
                        min="1"
                        max="23"
                        value={form.hourlyInterval}
                        onChange={(event) => onFormChange("hourlyInterval", event.target.value)}
                    />
                    <span>hours at minute</span>
                    <input
                        type="number"
                        min="0"
                        max="59"
                        value={form.hourlyMinute}
                        onChange={(event) => onFormChange("hourlyMinute", event.target.value)}
                    />
                </div>
            ) : null}

            {form.scheduleMode === "daily" ? (
                <div className="cron-schedule-row">
                    <span>Every day at</span>
                    <input
                        type="time"
                        value={normalizeTime(form.dailyTime)}
                        onChange={(event) => onFormChange("dailyTime", event.target.value)}
                    />
                </div>
            ) : null}

            {form.scheduleMode === "weekly" ? (
                <div className="cron-weekly-fields">
                    <div className="cron-weekday-picker" role="group" aria-label="Weekday">
                        {WEEKDAYS.map((day) => (
                            <button
                                key={day.value}
                                type="button"
                                className={String(form.weeklyDay) === day.value ? "active" : ""}
                                onClick={() => onFormChange("weeklyDay", day.value)}
                            >
                                {day.label}
                            </button>
                        ))}
                    </div>
                    <div className="cron-schedule-row">
                        <span>At</span>
                        <input
                            type="time"
                            value={normalizeTime(form.weeklyTime)}
                            onChange={(event) => onFormChange("weeklyTime", event.target.value)}
                        />
                    </div>
                </div>
            ) : null}

            {form.scheduleMode === "custom" ? (
                <input
                    value={form.schedule}
                    onChange={(event) => onFormChange("schedule", event.target.value)}
                    placeholder="*/5 * * * *"
                    autoFocus
                />
            ) : null}

            <div className="cron-schedule-preview">
                <span className="material-symbols-rounded" aria-hidden="true">schedule</span>
                <strong>{describeSchedule(form)}</strong>
                <code>{expression || "—"}</code>
            </div>
        </div>
    );
}

function ChannelSearchDropdown({
    availableChannels,
    selectedChannelId,
    isLoadingChannels,
    onSelect
}) {
    const [query, setQuery] = useState("");
    const [isOpen, setIsOpen] = useState(false);
    const selectedChannel = availableChannels.find((channel) => channel.channelId === selectedChannelId) || null;

    useEffect(() => {
        if (!isOpen) {
            setQuery(selectedChannel?.label || selectedChannelId || "");
        }
    }, [isOpen, selectedChannel?.label, selectedChannelId]);

    const filteredChannels = useMemo(() => {
        const normalizedQuery = query.trim().toLowerCase();
        if (!normalizedQuery) {
            return availableChannels;
        }

        return availableChannels.filter((channel) => {
            const label = String(channel.label || "").toLowerCase();
            const channelId = String(channel.channelId || "").toLowerCase();
            return label.includes(normalizedQuery) || channelId.includes(normalizedQuery);
        });
    }, [availableChannels, query]);

    function chooseChannel(channel) {
        onSelect(channel.channelId);
        setQuery(channel.label || channel.channelId);
        setIsOpen(false);
    }

    function handleKeyDown(event) {
        if (event.key === "Escape") {
            setIsOpen(false);
            return;
        }

        if (event.key === "Enter" && isOpen && filteredChannels.length > 0) {
            event.preventDefault();
            chooseChannel(filteredChannels[0]);
        }
    }

    return (
        <div className="actor-team-search-wrap cron-channel-search">
            <input
                className="actor-team-search"
                value={query}
                onChange={(event) => {
                    setQuery(event.target.value);
                    setIsOpen(true);
                }}
                onFocus={() => setIsOpen(true)}
                onBlur={() => setTimeout(() => setIsOpen(false), 150)}
                onKeyDown={handleKeyDown}
                placeholder={isLoadingChannels ? "Loading channels..." : "Search channels..."}
                disabled={isLoadingChannels || availableChannels.length === 0}
                autoComplete="off"
            />
            <span className="material-symbols-rounded cron-channel-chevron" aria-hidden="true">expand_more</span>
            {isOpen ? (
                <ul className="actor-team-dropdown">
                    {filteredChannels.length === 0 ? (
                        <li className="actor-team-dropdown-empty">No matching channels</li>
                    ) : (
                        filteredChannels.map((channel) => (
                            <li
                                key={channel.channelId}
                                className={`actor-team-dropdown-item ${channel.channelId === selectedChannelId ? "selected" : ""}`}
                                onMouseDown={(event) => {
                                    event.preventDefault();
                                    chooseChannel(channel);
                                }}
                            >
                                <span className="actor-team-dropdown-name">{channel.label}</span>
                                <span className="actor-team-dropdown-id">{channel.channelId}</span>
                            </li>
                        ))
                    )}
                </ul>
            ) : null}
        </div>
    );
}

function CronFormModal({
    isOpen,
    editingId,
    form,
    availableChannels,
    isLoadingChannels,
    isTesting,
    testStatus,
    onFormChange,
    onClose,
    onTest,
    onSubmit
}) {
    if (!isOpen) {
        return null;
    }

    const selectedChannel = availableChannels.find((channel) => channel.channelId === form.channelId) || null;
    const hasAvailableChannels = availableChannels.length > 0;

    return (
        <div className="project-modal-overlay" onClick={onClose}>
            <section className="project-modal" onClick={(e) => e.stopPropagation()}>
                <div className="project-modal-head">
                    <h3>{editingId ? "Edit Cron Job" : "New Cron Job"}</h3>
                    <button type="button" className="project-modal-close" aria-label="Close" onClick={onClose}>
                        ×
                    </button>
                </div>

                <form className="project-task-form" onSubmit={onSubmit}>
                    <div className="cron-field-block">
                        <span className="cron-field-label">Schedule</span>
                        <CronScheduleBuilder form={form} onFormChange={onFormChange} />
                    </div>

                    <label>
                        Command
                        <input
                            value={form.command}
                            onChange={(e) => onFormChange("command", e.target.value)}
                            placeholder="ping"
                        />
                    </label>

                    <div className="cron-field-block">
                        <span className="cron-field-label">Channel</span>
                        <ChannelSearchDropdown
                            availableChannels={availableChannels}
                            selectedChannelId={form.channelId}
                            isLoadingChannels={isLoadingChannels}
                            onSelect={(channelId) => onFormChange("channelId", channelId)}
                        />
                        {isLoadingChannels ? (
                            <span className="agent-field-note">Loading agent channels...</span>
                        ) : hasAvailableChannels ? (
                            <span className="agent-field-note">
                                {selectedChannel
                                    ? `Selected channel ID: ${selectedChannel.channelId}`
                                    : "Choose one of the linked channels available to this agent."}
                            </span>
                        ) : (
                            <span className="agent-field-note">
                                No linked channels found for this agent. Add one in the Channels tab first.
                            </span>
                        )}
                    </div>

                    <label className="cron-form-toggle">
                        <span>Enabled</span>
                        <span className="agent-tools-switch">
                            <input
                                type="checkbox"
                                checked={form.enabled}
                                onChange={(e) => onFormChange("enabled", e.target.checked)}
                            />
                            <span className="agent-tools-switch-track" />
                        </span>
                    </label>

                    {testStatus ? <p className="cron-test-status">{testStatus}</p> : null}

                    <div className="project-modal-actions cron-modal-actions">
                        <button
                            type="button"
                            className="cron-test-button"
                            onClick={onTest}
                            disabled={!buildScheduleExpression(form).trim() || !form.command.trim() || !form.channelId.trim() || isTesting}
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">science</span>
                            {isTesting ? "Testing..." : "Test"}
                        </button>
                        <div className="cron-modal-main-actions">
                            <button type="button" onClick={onClose}>
                                Cancel
                            </button>
                            <button
                                type="submit"
                                className="project-primary hover-levitate"
                                disabled={!buildScheduleExpression(form).trim() || !form.command.trim() || !form.channelId.trim()}
                            >
                                {editingId ? "Save Changes" : "Create Job"}
                            </button>
                        </div>
                    </div>
                </form>
            </section>
        </div>
    );
}

function emptyForm() {
    return { ...defaultScheduleFields(), command: "", channelId: "", enabled: true };
}

function normalizeChannels(board, agentId) {
    const nodes = Array.isArray(board?.nodes) ? board.nodes : [];
    const byId = new Map();

    for (const node of nodes) {
        if (String(node?.linkedAgentId || "") !== agentId) {
            continue;
        }

        const channelId = String(node?.channelId || "").trim();
        if (!channelId) {
            continue;
        }

        const displayName = String(node?.displayName || "").trim();
        byId.set(channelId, {
            channelId,
            label: displayName || channelId
        });
    }

    return Array.from(byId.values()).sort((left, right) => {
        const labelCompare = left.label.localeCompare(right.label, undefined, { sensitivity: "base" });
        if (labelCompare !== 0) {
            return labelCompare;
        }
        return left.channelId.localeCompare(right.channelId, undefined, { sensitivity: "base" });
    });
}

export function AgentCronTab({ agentId }) {
    const [tasks, setTasks] = useState([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState("");
    const [availableChannels, setAvailableChannels] = useState([]);
    const [isLoadingChannels, setIsLoadingChannels] = useState(true);

    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState(emptyForm());
    const [testingKey, setTestingKey] = useState("");
    const [testStatus, setTestStatus] = useState("");

    useEffect(() => {
        loadData();
    }, [agentId]);

    useEffect(() => {
        if (!isModalOpen || editingId || form.channelId.trim() || availableChannels.length === 0) {
            return;
        }

        setForm((previous) => ({
            ...previous,
            channelId: availableChannels[0].channelId
        }));
    }, [availableChannels, editingId, form.channelId, isModalOpen]);

    const modalChannels = useMemo(() => {
        if (!form.channelId.trim()) {
            return availableChannels;
        }

        const hasSelectedChannel = availableChannels.some((channel) => channel.channelId === form.channelId);
        if (hasSelectedChannel) {
            return availableChannels;
        }

        return [
            ...availableChannels,
            {
                channelId: form.channelId,
                label: `${form.channelId} (unlinked)`
            }
        ];
    }, [availableChannels, form.channelId]);

    async function loadData() {
        setIsLoading(true);
        setIsLoadingChannels(true);
        setError("");

        try {
            const [tasksResult, boardResult] = await Promise.all([
                fetchAgentCronTasks(agentId),
                fetchActorsBoard()
            ]);

            if (!tasksResult) {
                setError("Failed to fetch cron tasks.");
                setTasks([]);
            } else {
                setTasks(tasksResult);
            }

            if (!boardResult) {
                setAvailableChannels([]);
            } else {
                setAvailableChannels(normalizeChannels(boardResult, agentId));
            }
        } catch {
            setError("Failed to fetch cron tasks.");
            setTasks([]);
            setAvailableChannels([]);
        } finally {
            setIsLoading(false);
            setIsLoadingChannels(false);
        }
    }

    function handleOpenCreate() {
        setForm({
            ...emptyForm(),
            channelId: availableChannels[0]?.channelId || ""
        });
        setEditingId(null);
        setTestStatus("");
        setIsModalOpen(true);
    }

    function handleEdit(task) {
        setForm({
            ...scheduleFieldsFromExpression(task.schedule),
            command: task.command,
            channelId: task.channelId,
            enabled: task.enabled
        });
        setEditingId(task.id);
        setTestStatus("");
        setIsModalOpen(true);
    }

    function handleCloseModal() {
        setIsModalOpen(false);
        setEditingId(null);
        setTestStatus("");
    }

    function handleFormChange(field: string, value: string | boolean) {
        setForm((prev) => {
            if (field === "scheduleMode" && value === "custom") {
                return { ...prev, schedule: buildScheduleExpression(prev), [field]: value };
            }
            return { ...prev, [field]: value };
        });
    }

    async function handleDelete(taskId) {
        if (!window.confirm("Are you sure you want to delete this cron job?")) return;
        const success = await deleteAgentCronTask(agentId, taskId);
        if (success) {
            loadData();
        } else {
            alert("Failed to delete cron job.");
        }
    }

    async function handleToggle(task) {
        const success = await updateAgentCronTask(agentId, task.id, {
            ...task,
            enabled: !task.enabled
        });
        if (success) {
            loadData();
        } else {
            alert("Failed to toggle cron job.");
        }
    }

    async function handleTest(payload, testKey, showInlineStatus = false) {
        setTestingKey(testKey);
        if (showInlineStatus) {
            setTestStatus("");
        }

        try {
            const result = await sendChannelMessage(payload.channelId, {
                userId: "system_cron_test",
                content: cronTestContent(payload.command, payload.id || testKey),
                topicId: null
            });
            if (result) {
                if (showInlineStatus) {
                    setTestStatus(`Test sent to ${payload.channelId}.`);
                }
            } else {
                alert("Failed to send test.");
            }
        } catch {
            alert("Failed to send test.");
        } finally {
            setTestingKey("");
        }
    }

    async function handleTestDraft() {
        const payload = buildCronPayload(form);
        await handleTest({ ...payload, id: editingId || "draft" }, editingId || "draft", true);
    }

    async function handleTestTask(task) {
        await handleTest(task, task.id);
    }

    async function handleSubmit(e) {
        e.preventDefault();
        const payload = buildCronPayload(form);

        if (editingId) {
            const success = await updateAgentCronTask(agentId, editingId, payload);
            if (success) {
                handleCloseModal();
                loadData();
            } else {
                alert("Failed to update cron job.");
            }
        } else {
            const success = await createAgentCronTask(agentId, payload);
            if (success) {
                handleCloseModal();
                loadData();
            } else {
                alert("Failed to create cron job.");
            }
        }
    }

    return (
        <>
            <CronFormModal
                isOpen={isModalOpen}
                editingId={editingId}
                form={form}
                availableChannels={modalChannels}
                isLoadingChannels={isLoadingChannels}
                isTesting={testingKey === (editingId || "draft")}
                testStatus={testStatus}
                onFormChange={handleFormChange}
                onClose={handleCloseModal}
                onTest={handleTestDraft}
                onSubmit={handleSubmit}
            />

            <div className="agent-content-card entry-editor-card">
                <div className="agent-content-header">
                    <h3>Cron Jobs</h3>
                    {tasks.length > 0 && (
                        <button type="button" className="text-button" onClick={handleOpenCreate}>
                            + New Job
                        </button>
                    )}
                </div>

                {error ? (
                    <p className="agent-field-note" style={{ color: "var(--critical)" }}>{error}</p>
                ) : null}

                {isLoading ? (
                    <p className="placeholder-text">Loading...</p>
                ) : tasks.length === 0 ? (
                    <div className="cron-empty-stage">
                        <span className="material-symbols-rounded cron-empty-icon">timer</span>
                        <h4 className="cron-empty-title">No cron jobs yet</h4>
                        <p className="cron-empty-desc">
                            Schedule automated tasks that run on a timer and<br />
                            deliver results to messaging channels
                        </p>
                        <button type="button" className="agent-empty-create hover-levitate" onClick={handleOpenCreate}>
                            + New Job
                        </button>
                    </div>
                ) : (
                    <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem" }}>
                        {tasks.map((task) => (
                            <div key={task.id} className="cron-task-row">
                                <div className="cron-task-info">
                                    <span className="cron-task-schedule-text">{describeCronExpression(task.schedule)}</span>
                                    <code className="cron-task-schedule">{task.schedule}</code>
                                    <span className="cron-task-command">{task.command}</span>
                                    <span className="cron-task-channel">
                                        <span className="material-symbols-rounded" style={{ fontSize: 13 }}>send</span>
                                        {task.channelId}
                                    </span>
                                </div>
                                <div className="cron-task-actions">
                                    <label className="cron-task-toggle">
                                        <span className="agent-tools-switch">
                                            <input
                                                type="checkbox"
                                                checked={task.enabled}
                                                onChange={() => handleToggle(task)}
                                            />
                                            <span className="agent-tools-switch-track" />
                                        </span>
                                        <span>{task.enabled ? "Active" : "Paused"}</span>
                                    </label>
                                    <button
                                        type="button"
                                        className="text-button"
                                        disabled={testingKey === task.id}
                                        onClick={() => handleTestTask(task)}
                                    >
                                        {testingKey === task.id ? "Testing..." : "Test"}
                                    </button>
                                    <button
                                        type="button"
                                        className="text-button"
                                        onClick={() => handleEdit(task)}
                                    >
                                        Edit
                                    </button>
                                    <button
                                        type="button"
                                        className="text-button"
                                        style={{ color: "var(--critical)" }}
                                        onClick={() => handleDelete(task.id)}
                                    >
                                        Delete
                                    </button>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </>
    );
}
