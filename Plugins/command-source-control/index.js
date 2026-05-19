#!/usr/bin/env node
"use strict";

const { execFile } = require("node:child_process");
const fs = require("node:fs/promises");
const path = require("node:path");

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

function valueAt(object, key, fallback = undefined) {
  return object && Object.prototype.hasOwnProperty.call(object, key) ? object[key] : fallback;
}

function commandConfig(manifest, key) {
  return valueAt(valueAt(manifest.config, "commands", {}), key);
}

function worktreePath(manifest, repoPath, taskId, worktreeRootPath) {
  if (worktreeRootPath) return path.join(worktreeRootPath, taskId);
  const rootName = valueAt(manifest.config, "worktreeRootName", ".sloppy-worktrees");
  return path.join(repoPath, rootName, taskId);
}

function branchNameFor(taskId) {
  return `sloppy/${taskId}`;
}

function renderTemplate(value, context) {
  return String(value).replace(/\{([A-Za-z0-9_]+)\}/g, (_, key) => {
    return Object.prototype.hasOwnProperty.call(context, key) ? String(context[key]) : "";
  });
}

function commandToExecutable(command, context) {
  if (Array.isArray(command)) {
    if (command.length === 0) return null;
    return {
      executable: renderTemplate(command[0], context),
      args: command.slice(1).map((part) => renderTemplate(part, context)),
      shell: false
    };
  }
  if (typeof command === "string" && command.trim()) {
    return {
      executable: "/bin/sh",
      args: ["-lc", renderTemplate(command, context)],
      shell: true
    };
  }
  return null;
}

function runCommand(command, context, cwd) {
  const spec = commandToExecutable(command, context);
  if (!spec) {
    const error = new Error(`Unsupported source-control operation: ${context.method}`);
    error.code = "unsupported";
    throw error;
  }
  return new Promise((resolve, reject) => {
    execFile(spec.executable, spec.args, {
      cwd,
      env: { ...process.env },
      maxBuffer: valueAt(context, "maxBytes", 1024 * 1024)
    }, (error, stdout, stderr) => {
      if (error) {
        error.message = [stdout, stderr, error.message].filter(Boolean).join("\n");
        reject(error);
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}

function lineStats(text) {
  let linesAdded = 0;
  let linesDeleted = 0;
  for (const line of String(text || "").split("\n")) {
    if (line.startsWith("+") && !line.startsWith("+++")) linesAdded += 1;
    if (line.startsWith("-") && !line.startsWith("---")) linesDeleted += 1;
  }
  return { linesAdded, linesDeleted };
}

async function handle(request) {
  const manifest = request.manifest || {};
  const params = request.params || {};
  const method = request.method;
  const repoPath = params.repoPath || params.path;
  const taskId = params.taskId;
  const branchName = params.branchName || (taskId ? branchNameFor(taskId) : "");
  const computedWorktreePath = params.worktreePath || (repoPath && taskId ? worktreePath(manifest, repoPath, taskId, params.worktreeRootPath) : "");
  const context = {
    method,
    repoPath,
    path: params.path,
    taskId,
    worktreeRootPath: params.worktreeRootPath || "",
    worktreePath: computedWorktreePath,
    branchName,
    baseBranch: params.baseBranch || "HEAD",
    targetBranch: params.targetBranch || "main",
    relativePath: params.relativePath || "",
    maxBytes: params.maxBytes || 1024 * 1024
  };

  if (method === "worktreePath") {
    return computedWorktreePath;
  }

  if (method === "createWorktree") {
    await fs.mkdir(path.dirname(computedWorktreePath), { recursive: true });
    await runCommand(commandConfig(manifest, "createWorktree"), context, repoPath);
    return { worktreePath: computedWorktreePath, branchName };
  }

  if (method === "removeWorktree") {
    await runCommand(commandConfig(manifest, "removeWorktree"), context, repoPath);
    return {};
  }

  if (method === "inspectRepository") {
    const command = commandConfig(manifest, "inspectRepository");
    if (!command) {
      return { providerId: manifest.name, isRepository: true, rootPath: params.path || repoPath };
    }
    const output = await runCommand(command, context, params.path || repoPath);
    const text = output.stdout.trim();
    if (text.startsWith("{")) return JSON.parse(text);
    return { providerId: manifest.name, isRepository: true, rootPath: params.path || repoPath, message: text || null };
  }

  if (method === "workingTreeDiff" || method === "branchDiff") {
    const output = await runCommand(commandConfig(manifest, method), context, params.path || repoPath);
    const stats = lineStats(output.stdout);
    return {
      providerId: manifest.name,
      baseRef: context.baseBranch,
      headRef: method === "branchDiff" ? context.branchName : null,
      text: output.stdout,
      truncated: false,
      files: [],
      ...stats
    };
  }

  if (method === "workingTreeStatus") {
    const command = commandConfig(manifest, "workingTreeStatus");
    if (!command) {
      return {
        repository: { providerId: manifest.name, isRepository: true, rootPath: params.path || repoPath },
        files: [],
        linesAdded: 0,
        linesDeleted: 0
      };
    }
    const output = await runCommand(command, context, params.path || repoPath);
    const text = output.stdout.trim();
    if (text.startsWith("{")) return JSON.parse(text);
    const stats = lineStats(text);
    return {
      repository: { providerId: manifest.name, isRepository: true, rootPath: params.path || repoPath },
      files: [],
      ...stats
    };
  }

  if (method === "currentBranch" || method === "defaultBranch") {
    const output = await runCommand(commandConfig(manifest, method), context, params.path || repoPath);
    return output.stdout.trim() || null;
  }

  if (method === "restorePathFromHead" || method === "mergeBranch") {
    await runCommand(commandConfig(manifest, method), context, repoPath);
    return {};
  }

  const error = new Error(`Unsupported source-control operation: ${method}`);
  error.code = "unsupported";
  throw error;
}

(async () => {
  const input = (await readStdin()).trim().split("\n").find(Boolean);
  if (!input) return;
  const request = JSON.parse(input);
  try {
    const result = await handle(request);
    process.stdout.write(`${JSON.stringify({ id: request.id, result: result === undefined ? null : result })}\n`);
  } catch (error) {
    process.stdout.write(`${JSON.stringify({
      id: request.id,
      error: {
        code: error.code || "failed",
        message: error.message || String(error)
      }
    })}\n`);
  }
})().catch((error) => {
  process.stderr.write(`${error.stack || error.message || String(error)}\n`);
  process.exit(1);
});
