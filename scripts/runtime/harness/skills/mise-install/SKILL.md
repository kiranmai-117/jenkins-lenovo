---
name: mise-install
description: Install missing language runtimes and developer tools with mise on demand. Use when a repo needs tools such as Java, Maven, Gradle, Go, Python, Node.js, npm, pnpm, yarn, or when commands fail because a runtime, compiler, package manager, linter, or test tool is missing.
---

# Mise Install

Use `mise` to install only the tools needed for the current repository task. Prefer repository-declared versions over guessing.

## When to Use

Use this skill before running tests, linters, builds, or code generators if a required tool is missing or the repo declares a tool version.

Common triggers:

- `mvn`, `java`, `gradle`, `go`, `python`, `node`, `npm`, `pnpm`, `yarn`, `ruff`, or another command is missing.
- The repo has `.mise.toml`, `.tool-versions`, `mise.toml`, `pom.xml`, `build.gradle`, `go.mod`, `pyproject.toml`, `package.json`, or similar toolchain files.
- The task asks to run tests/lint/build and the needed runtime is not already available.

## Workflow

1. Check existing tools:

```bash
command -v mise || true
mise --version || true
```

2. Read repo tool declarations first:

```bash
ls -la .mise.toml mise.toml .tool-versions go.mod pom.xml build.gradle build.gradle.kts pyproject.toml package.json 2>/dev/null || true
```

3. If the repo declares versions, trust those files:

```bash
mise install
eval "$(mise activate bash)"
```

4. If the repo does not declare a version, read `preferred-tool-versions.yaml` from this skill directory and install only the needed tool explicitly. This YAML file is the source of truth for preferred defaults.

```bash
VERSIONS_FILE=""
for candidate in \
  ".agents/skills/mise-install/preferred-tool-versions.yaml" \
  ".claude/skills/mise-install/preferred-tool-versions.yaml" \
  "${HOME}/.agents/skills/mise-install/preferred-tool-versions.yaml" \
  "${HOME}/.claude/skills/mise-install/preferred-tool-versions.yaml"; do
  if [ -f "$candidate" ]; then
    VERSIONS_FILE="$candidate"
    break
  fi
done

cat "$VERSIONS_FILE"

# Example: install only one needed default from the config.
mise install go@$(awk -F': *' '$1 ~ /go/ {gsub(/"/, "", $2); print $2}' "$VERSIONS_FILE")
eval "$(mise activate bash)"
```

5. Verify before continuing:

```bash
go version || true
java -version || true
mvn -version || true
python --version || true
node --version || true
```

## Preferred Versions

Preferred default versions live in `preferred-tool-versions.yaml`. Use them only when the repo does not declare a version and the task requires the tool.

## Notes

- Do not install every tool preemptively.
- Keep tool installation local to the CI container; do not commit `.mise.toml`, `.tool-versions`, lockfiles, or generated files unless the task explicitly requires it.
- If a project uses a wrapper (`mvnw`, `gradlew`), prefer the wrapper after installing the required runtime.
