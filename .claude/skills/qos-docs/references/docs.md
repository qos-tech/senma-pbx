# Documentation Maintenance Guide

## Source of truth

Repository evidence takes precedence over assumptions.

Inspect, when available:

- source code;
- manifests and lockfiles;
- command-line help;
- configuration schemas;
- scripts;
- tests;
- CI workflows;
- architecture decisions;
- changelogs;
- existing documentation;
- release and packaging configuration.

When repository evidence is incomplete or contradictory, state the uncertainty instead of guessing.

## Canonical documentation

When multiple languages or variants exist:

1. Identify the canonical document from repository policy or the user's instruction.
2. Update the canonical document first.
3. Synchronize translations and secondary variants afterward.
4. Preserve equivalent meaning, capabilities, warnings, and examples.
5. Do not allow translated documents to advertise different behavior.

If no canonical document is defined, ask or infer conservatively from repository conventions and explain the choice.

## README guidance

A README should normally help a new contributor or adopter understand:

- what the project is;
- what problem it solves;
- current maturity or status, when relevant;
- key capabilities;
- prerequisites;
- installation;
- quick start;
- common workflows;
- configuration;
- testing and validation;
- project structure, when useful;
- contribution expectations;
- license and attribution.

Include only sections that add value to the actual project.

## Audience-first organization

Place adoption-oriented information before internal architecture unless the request is specifically aimed at maintainers.

A common order is:

1. Project name and purpose
2. Key capabilities
3. Requirements
4. Installation
5. Quick start
6. Usage
7. Configuration
8. Validation and testing
9. Architecture or repository structure
10. Contributing
11. License

This is guidance, not a mandatory template.

## Verification rules

Before documenting a command:

- confirm the executable or script exists;
- confirm the arguments and flags;
- confirm the expected working directory;
- confirm required environment variables;
- check exit behavior when relevant.

Before documenting a configuration field:

- confirm its exact name;
- confirm its type and accepted values;
- confirm precedence and default behavior;
- confirm whether it may contain secrets;
- avoid publishing real secret values.

Before documenting a feature:

- locate its implementation or authoritative decision;
- determine whether it is stable, experimental, optional, or planned;
- confirm supported environments and limitations.

Before documenting a path:

- confirm casing and location;
- distinguish source paths from installed/generated paths;
- distinguish tracked files from local or ignored files.

## Examples

Examples should be:

- minimal;
- executable or mechanically verifiable when possible;
- free of real credentials;
- consistent with the project's current interface;
- explicit about placeholders;
- safe to copy.

Do not use an output format from one implementation as a universal contract unless the repository defines it as such.

## Translation

Translations must preserve:

- technical meaning;
- support boundaries;
- warnings;
- command names;
- filenames and paths;
- configuration keys;
- status labels;
- license and attribution.

Commands, identifiers, filenames, environment variables, and code usually remain untranslated.

Natural phrasing may differ, but capabilities and limitations must remain equivalent.

## Writing style

- Prefer direct, precise language.
- Use short sections and examples.
- Introduce terminology before relying on it.
- Avoid unnecessary claims such as “production-ready”, “enterprise-grade”, or “secure” without evidence.
- Avoid excessive internal implementation detail in introductory sections.
- Use consistent names and capitalization.
- Make limitations visible near the related feature.

## Documentation tests

Add or update deterministic documentation checks when they protect real contracts, for example:

- referenced scripts exist;
- documented commands match CLI help;
- configuration examples parse;
- required README sections exist;
- translated command tables remain aligned;
- examples execute in an isolated environment.

Avoid brittle tests that fail on harmless wording changes.

## Completion report

At completion, report:

- documents created or changed;
- obsolete content removed;
- commands and examples validated;
- checks executed;
- unresolved discrepancies;
- any content intentionally left unchanged.
