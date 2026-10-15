# Agents play through a CLI inside a coding-agent harness

The Agent is a general coding agent (e.g. Claude Code) that plays by running `ftl` CLI commands in a shell, not a custom runner calling model APIs with our own tool schema. This matches how agents are actually deployed, at the cost of mixing each harness's own prompt and behaviour into results, so comparisons are per harness+model, not per model alone.
