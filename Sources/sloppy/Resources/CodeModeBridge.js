((inputJSON, script) => {
    "use strict";
    const parse = JSON.parse;
    const stringify = JSON.stringify;
    const { catalog, stored } = parse(inputJSON);
    const entries = new Map(catalog.map(entry => [entry.name, entry]));
    const aliases = new Map();
    for (const entry of catalog) {
        const alias = entry.name.replace(/[^a-zA-Z0-9_$]/g, "_");
        aliases.set(alias, aliases.has(alias) ? null : entry.name);
    }
    const allTools = Object.freeze(catalog.map(({ name, description }) => Object.freeze({ name, description })));
    const pending = new Map();
    const writes = Object.create(null);
    const output = { head: "" };
    const logs = { head: "" };
    const exitSignal = Symbol();
    let requests = [];
    let nextID = 0;
    let finished = false;
    let error;

    function append(stream, value) {
        if (value === undefined) return;
        const line = typeof value === "string" ? value : stringify(value);
        if (line === undefined) return;
        const chunk = (stream.hasItems ? "\n" : "") + line;
        stream.hasItems = true;
        const combined = (stream.tail ?? stream.head) + chunk;
        if (stream.tail === undefined) {
            if (combined.length <= 40_000) {
                stream.head = combined;
                return;
            }
            const boundary = combined.charCodeAt(19_999);
            const end = boundary >= 0xd800 && boundary <= 0xdbff ? 19_999 : 20_000;
            stream.head = combined.slice(0, end);
        }
        const start = Math.max(0, combined.length - 20_000);
        const boundary = combined.charCodeAt(start);
        stream.tail = combined.slice(boundary >= 0xdc00 && boundary <= 0xdfff ? start + 1 : start);
    }

    function call(name, argumentsObject = {}) {
        if (!entries.has(name)) throw new Error(`Tool unavailable: ${name}`);
        if (nextID === 64) throw new Error("Script exceeded its 64 tool calls");
        if (!argumentsObject || typeof argumentsObject !== "object" || Array.isArray(argumentsObject)) {
            throw new TypeError("Tool arguments must be an object");
        }
        const id = ++nextID;
        const args = parse(stringify(argumentsObject));
        requests.push({ id, name, arguments: args });
        return new Promise(resolve => pending.set(id, resolve));
    }

    const tools = new Proxy(Object.create(null), {
        get(_, name) {
            if (name === "call") return call;
            if (typeof name !== "string" || name === "then") return undefined;
            const id = entries.has(name) ? name : aliases.get(name);
            if (id) return args => call(id, args);
            return undefined;
        }
    });

    function searchTools(query, { limit = 8, namespace } = {}) {
        const words = String(query).toLowerCase().split(/\s+/).filter(Boolean);
        return catalog
            .filter(entry => namespace === undefined || entry.namespace === namespace)
            .map(entry => ({
                entry,
                score: words.reduce((score, word) => score
                    + (entry.name.toLowerCase().includes(word) ? 3 : 0)
                    + (entry.description.toLowerCase().includes(word) ? 1 : 0), 0)
            }))
            .filter(({ score }) => !words.length || score > 0)
            .sort((a, b) => b.score - a.score)
            .slice(0, Math.min(64, Math.max(0, limit)))
            .map(({ entry: { name, description } }) => ({ name, description }));
    }

    function describeTool(name) {
        const entry = entries.get(name) ?? entries.get(aliases.get(name));
        return entry === undefined ? undefined : parse(stringify(entry));
    }

    function describeNamespace(name) {
        const tools = searchTools("", { limit: 64, namespace: name });
        return tools.length ? { name, tools } : undefined;
    }

    function store(key, value) {
        if (typeof key !== "string" || !key.length || key.length > 128) throw new Error("Invalid store key");
        const encoded = stringify(value);
        if (encoded === undefined || encoded.length > 8192) throw new Error("Store value must be small JSON");
        if (!Object.hasOwn(writes, key) && Object.keys(writes).length >= 32) throw new Error("Too many store keys");
        writes[key] = parse(encoded);
    }

    const log = (...items) => append(logs, items.map(value =>
        typeof value === "string" ? value : (stringify(value) ?? String(value))
    ).join(" "));
    const globals = {
        tools, ALL_TOOLS: allTools, searchTools, describeTool, describeNamespace, store,
        load: key => Object.hasOwn(writes, key) ? writes[key] : (Object.hasOwn(stored, key) ? stored[key] : undefined),
        text: value => append(output, value),
        console: Object.freeze({ log, info: log, warn: log, error: log, debug: log }),
        exit: () => { throw exitSignal; }
    };
    for (const [name, value] of Object.entries(globals)) {
        Object.defineProperty(globalThis, name, { value });
    }

    async function run() {
        try {
            const execute = (0, eval)("(async () => { \"use strict\";\n" + script + "\n})");
            append(output, await execute());
        } catch (cause) {
            if (cause !== exitSignal) error = String(cause).slice(0, 1024);
        } finally {
            finished = true;
        }
    }
    Promise.resolve().then(run);

    return (completionJSON, snapshot) => {
        if (completionJSON) {
            const { id, result } = parse(completionJSON);
            const resume = pending.get(id);
            pending.delete(id);
            if (resume) resume(result);
        }
        if (!snapshot) return "";
        const state = finished
            ? { finished, error, output, logs, writes, requests: [] }
            : { finished, requests };
        requests = [];
        return stringify(state);
    };
})
