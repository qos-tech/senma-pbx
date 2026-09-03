---
description: Design plugin providing UI/UX analysis, interface redesign guidance, design-system enforcement, visual consistency review, and implementation-oriented frontend recommendations.
argument-hint: '[description | path-to-screenshot-or-component]'
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# qos-design

Provide a consistent design and UI/UX engineering capability for Harness workflows. The plugin helps an execution engine analyze an existing interface, identify visual and usability problems, propose structured redesigns, preserve existing product identity, define or apply a design system, review implementation fidelity, guide frontend implementation, validate responsive behavior, validate accessibility fundamentals, and avoid generic or visually inconsistent output.

## Capabilities

1. **UI Analysis**: Analyze screens, screenshots, components, routes, frontend code, and existing design tokens. Identify issues involving hierarchy, spacing, alignment, density, typography, color, contrast, component consistency, navigation, responsive behavior, accessibility, interaction states, empty states, loading states, error states, and visual identity.
2. **Design System Discovery**: Before proposing changes, inspect the project for existing colors, typography, spacing scales, border radii, shadows, icons, buttons, inputs, cards, dialogs, navigation patterns, light and dark themes, responsive breakpoints, and reusable components. Prefer reuse and consolidation over introducing arbitrary new patterns.
3. **Redesign Planning**: Produce implementation-oriented redesign guidance containing observed problems, design goals, preserved behaviors, visual direction, component changes, layout changes, responsive rules, interaction states, accessibility considerations, implementation sequence, and a validation checklist.
4. **Frontend Implementation Guidance**: When implementation is requested, inspect the existing frontend stack, reuse the current component library, reuse existing design tokens, preserve business behavior, avoid unnecessary rewrites, avoid hardcoded one-off styling when reusable tokens exist, keep light and dark themes consistent, maintain responsive behavior, and add or update tests when the repository supports them.
5. **Visual Review**: Review a completed implementation against a screenshot, a design reference, a written design specification, or the project's existing design system. Distinguish between functional correctness, visual fidelity, design-system consistency, responsive correctness, and accessibility fundamentals.
6. **Design Identity**: Explicitly avoid generic AI-generated interfaces. Encourage deliberate visual hierarchy, consistent spacing rhythm, clear product identity, coherent iconography, consistent component geometry, meaningful color usage, polished empty and loading states, restrained use of effects, and visual consistency across routes.

## Behavioral Rules

1. Inspect before redesigning.
2. Preserve working product behavior unless the task explicitly changes it.
3. Reuse the project's existing design language whenever possible.
4. Do not redesign unrelated areas.
5. Do not introduce a new UI framework without explicit justification.
6. Do not replace existing reusable components with local copies.
7. Do not hardcode colors when semantic design tokens are available.
8. Treat light and dark themes as equally important when both exist.
9. Consider desktop, tablet, and mobile behavior.
10. Include hover, focus, active, disabled, loading, empty, success, warning, and error states where applicable.
11. Treat accessibility as part of design quality, not as an optional follow-up.
12. Provide implementation-ready guidance instead of vague aesthetic opinions.
13. Clearly separate observations, proposed changes, implementation work, and validation results.
14. Never claim visual fidelity without evidence or an explicit validation step.

## Output Contract

When qos-design produces a design analysis or redesign specification, prefer the following structure:
1. Context
2. Current State
3. Problems Found
4. Design Goals
5. Visual Direction
6. Design System Decisions
7. Layout and Component Changes
8. Responsive Behavior
9. Interaction and State Rules
10. Accessibility Considerations
11. Implementation Plan
12. Validation Checklist

Adapt the structure when the request is narrower, but keep outputs implementation-oriented.
