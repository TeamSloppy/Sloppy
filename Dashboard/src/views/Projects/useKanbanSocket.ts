import { useEffect, useRef } from "react";
import { buildWebSocketURL } from "../../shared/api/httpClient";

export type KanbanEventType = "task_created" | "task_updated" | "task_deleted" | "project_updated";

export interface KanbanEvent {
  type: KanbanEventType;
  projectId: String;
  task?: any;
  taskId?: String;
}

const RECONNECT_DELAY_MS = 3000;

export function useKanbanSocket(projectId: string, onEvent: (event: KanbanEvent) => void) {
  const onEventRef = useRef(onEvent);
  onEventRef.current = onEvent;

  useEffect(() => {
    if (!projectId) return;

    let socket: WebSocket | null = null;
    let reconnectTimer: number | null = null;
    let disposed = false;

    function connect() {
      if (disposed) return;

      const url = buildWebSocketURL(`/v1/projects/${projectId}/kanban/ws`);
      socket = new WebSocket(url);

      socket.onmessage = (msg) => {
        if (!msg?.data) return;
        try {
          const payload = JSON.parse(String(msg.data)) as KanbanEvent;
          if (payload && payload.type) {
            onEventRef.current(payload);
          }
        } catch (e) {
          console.warn("Malformed kanban event", e);
        }
      };

      socket.onclose = () => {
        socket = null;
        if (disposed) return;
        reconnectTimer = window.setTimeout(() => {
          reconnectTimer = null;
          connect();
        }, RECONNECT_DELAY_MS);
      };

      socket.onerror = () => {
        socket?.close();
      };
    }

    connect();

    return () => {
      disposed = true;
      if (reconnectTimer != null) {
        window.clearTimeout(reconnectTimer);
      }
      if (socket) {
        socket.close();
        socket = null;
      }
    };
  }, [projectId]);
}
