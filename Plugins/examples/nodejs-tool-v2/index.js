import { definePlugin, z } from "@sloppy/plugin";

export default definePlugin((ctx) => {
  ctx.registerTool({
    name: "weather.current",
    title: "Current Weather",
    description: "Returns a deterministic weather sample for a city.",
    schema: z.object({
      city: z.string()
    }),
    async invoke(arguments_) {
      return {
        city: arguments_.city,
        temperature: 22,
        condition: "sunny"
      };
    }
  });
});
