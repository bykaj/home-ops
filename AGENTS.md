@.agents/instructions/sorting.instructions.md

Reusable task skills (add-app, add-docker-app, ...) live in `.agents/skills/`; Claude Code discovers them through the `.claude/skills` symlink.

## MCP servers

When looking up how to deploy or configure something, use the kubesearch MCP server first: real-world manifests and Helm values from home-ops repos, including the reference repos. Use Context7 only as a fallback for upstream library or API reference docs that kubesearch and the repo's own `docs/` don't answer (for example a CRD field or chart option newer than your knowledge).
