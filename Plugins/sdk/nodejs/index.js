const objectSchema = (properties = {}, required = []) => ({
  type: "object",
  properties,
  required
});

function schemaBuilder(schema) {
  return {
    toJSONSchema() {
      return schema;
    },
    optional() {
      return { ...schemaBuilder(schema), isOptional: true };
    }
  };
}

export const z = {
  string: () => schemaBuilder({ type: "string" }),
  number: () => schemaBuilder({ type: "number" }),
  boolean: () => schemaBuilder({ type: "boolean" }),
  array: (item) => schemaBuilder({ type: "array", items: toJSONSchema(item) }),
  object: (shape) => {
    const properties = {};
    const required = [];
    for (const [key, value] of Object.entries(shape)) {
      properties[key] = toJSONSchema(value);
      if (!value?.isOptional) required.push(key);
    }
    return schemaBuilder(objectSchema(properties, required));
  }
};

export function definePlugin(factory) {
  const registry = {
    tools: new Map(),
    hooks: new Map(),
    commands: new Map(),
    skills: new Map(),
    gateways: new Map(),
    sourceControls: new Map(),
    memories: new Map(),
    modelProviders: new Map()
  };

  const ctx = {
    registerTool(definition) {
      requireFields(definition, ["name", "title", "description", "invoke"], "tool");
      registry.tools.set(definition.name, {
        ...definition,
        inputSchema: toJSONSchema(definition.inputSchema || definition.schema)
      });
    },
    registerHook(name, handler) {
      registry.hooks.set(name, { name, handler });
    },
    registerCommand(definition) {
      requireFields(definition, ["name", "run"], "command");
      registry.commands.set(definition.name, definition);
    },
    registerSkill(definition) {
      requireFields(definition, ["name"], "skill");
      registry.skills.set(definition.name, definition);
    },
    registerGateway(definition) {
      requireFields(definition, ["name"], "gateway");
      registry.gateways.set(definition.name, definition);
    },
    registerSourceControl(definition) {
      requireFields(definition, ["name"], "source control");
      registry.sourceControls.set(definition.name, definition);
    },
    registerMemory(definition) {
      requireFields(definition, ["name"], "memory");
      registry.memories.set(definition.name, definition);
    },
    registerModelProvider(definition) {
      requireFields(definition, ["name"], "model provider");
      registry.modelProviders.set(definition.name, definition);
    }
  };

  factory(ctx);
  startProtocolLoop(registry);
  return { registry };
}

function toJSONSchema(value) {
  if (!value) return objectSchema();
  if (typeof value.toJSONSchema === "function") return value.toJSONSchema();
  return value;
}

function requireFields(value, fields, kind) {
  for (const field of fields) {
    if (value?.[field] === undefined || value[field] === "") {
      throw new Error(`Missing ${kind} field: ${field}`);
    }
  }
}

function runtimeFor(request) {
  const callHost = async (method, params = {}) => {
    throw new Error(`Runtime service ${method} is not available in one-shot stdio mode yet.`);
  };
  return {
    tools: { invoke: (name, args) => callHost("runtime.tools.invoke", { name, args }) },
    secrets: { get: (name) => callHost("runtime.secrets.get", { name }) },
    store: {
      get: (key) => callHost("runtime.store.get", { key }),
      set: (key, value) => callHost("runtime.store.set", { key, value })
    },
    llm: { complete: (params) => callHost("runtime.llm.complete", params) },
    events: { emit: (name, payload) => callHost("runtime.events.emit", { name, payload }) },
    log: {
      info: (...values) => process.stderr.write(`${values.join(" ")}\n`),
      warn: (...values) => process.stderr.write(`${values.join(" ")}\n`),
      error: (...values) => process.stderr.write(`${values.join(" ")}\n`)
    },
    manifest: request.manifest
  };
}

async function dispatch(request, registry) {
  if (request.method === "plugin.describe") {
    return {
      tools: [...registry.tools.values()].map((tool) => ({
        name: tool.name,
        title: tool.title,
        description: tool.description,
        inputSchema: tool.inputSchema || objectSchema()
      })),
      hooks: names(registry.hooks),
      commands: names(registry.commands),
      skills: names(registry.skills),
      gateways: names(registry.gateways),
      source_control: [...registry.sourceControls.values()].map((sourceControl) => ({
        name: sourceControl.name,
        displayName: sourceControl.displayName || sourceControl.name,
        capabilities: sourceControl.capabilities || []
      })),
      memory: names(registry.memories),
      providers: names(registry.modelProviders)
    };
  }

  if (request.method === "tool.invoke") {
    const tool = registry.tools.get(request.params?.tool);
    if (!tool) throw unsupported(`Unknown tool: ${request.params?.tool}`);
    return await tool.invoke(request.params?.arguments || {}, runtimeFor(request));
  }

  if (request.method === "hook.dispatch") {
    const hook = registry.hooks.get(request.params?.name);
    if (!hook) throw unsupported(`Unknown hook: ${request.params?.name}`);
    return await hook.handler(request.params?.event || {}, runtimeFor(request));
  }

  if (request.method === "command.run") {
    const command = registry.commands.get(request.params?.command);
    if (!command) throw unsupported(`Unknown command: ${request.params?.command}`);
    return await command.run(request.params?.arguments || {}, runtimeFor(request));
  }

  if (request.method?.startsWith("source_control.")) {
    const sourceControl = [...registry.sourceControls.values()][0];
    const operation = request.method.slice("source_control.".length);
    const handler = sourceControl?.[operation];
    if (typeof handler !== "function") throw unsupported(`Unsupported source-control operation: ${operation}`);
    return await handler(request.params || {}, runtimeFor(request));
  }

  throw unsupported(`Unsupported method: ${request.method}`);
}

function names(map) {
  return [...map.values()].map((item) => ({
    name: item.name,
    title: item.title,
    description: item.description
  }));
}

function unsupported(message) {
  const error = new Error(message);
  error.code = "unsupported";
  return error;
}

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

function serializeError(error) {
  return {
    code: error.code || "failed",
    message: error.message || String(error)
  };
}

async function startProtocolLoop(registry) {
  try {
    const line = (await readStdin()).trim().split("\n").find(Boolean);
    if (!line) return;
    const request = JSON.parse(line);
    try {
      const result = await dispatch(request, registry);
      process.stdout.write(`${JSON.stringify({ id: request.id, result: result === undefined ? null : result })}\n`);
    } catch (error) {
      process.stdout.write(`${JSON.stringify({ id: request.id, error: serializeError(error) })}\n`);
    }
  } catch (error) {
    process.stderr.write(`${error.stack || error.message || String(error)}\n`);
    process.exitCode = 1;
  }
}
