import { definePlugin } from "@sloppy/plugin";

export default definePlugin((ctx) => {
  ctx.registerSourceControl({
    name: "example-source-control",
    displayName: "Example Source Control",
    capabilities: ["worktrees"],
    async createWorktree(params) {
      return {
        worktreePath: `${params.repoPath}/.sloppy-worktrees/${params.taskId}`,
        branchName: `sloppy/${params.taskId}`
      };
    }
  });
});
