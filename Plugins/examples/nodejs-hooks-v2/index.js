import { definePlugin } from "@sloppy/plugin";

export default definePlugin((ctx) => {
  ctx.registerHook("post_tool_call", async (event, runtime) => {
    runtime.log.info("post_tool_call", JSON.stringify({
      tool: event.tool,
      ok: event.ok
    }));
  });
});
