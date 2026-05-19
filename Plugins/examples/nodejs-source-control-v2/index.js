import { definePlugin } from "@sloppy/plugin";

export default definePlugin((ctx) => {
  ctx.registerSourceControl({
    name: "example-source-control",
    displayName: "Example Source Control",
    capabilities: ["worktrees"],
    async createWorktree(params) {
      const rootPath = params.worktreeRootPath || `${params.repoPath}/.sloppy-worktrees`;
      return {
        worktreePath: `${rootPath}/${params.taskId}`,
        branchName: `sloppy/${params.taskId}`
      };
    }
  });
});
