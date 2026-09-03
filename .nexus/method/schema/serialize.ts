/**
 * Writes the shapes the parsers read. The two are a pair: everything this
 * file emits must round-trip through parseBoard/parseIssue unchanged, and the
 * battery holds that promise with real tricky text.
 */

import type { Board, BoardItem, Comment, Criterion, Issue, IssueArtifact, Spec, Task } from './types'

/** Bare only when unambiguous; otherwise double quotes with the three
 *  escapes unquote() decodes. Newlines survive as \n on one physical line. */
export function scalar(text: string): string {
  const reserved = /^(true|false|null|~|-?\d+(\.\d+)?)$/
  /* Punctuation an ordinary title carries stays bare: none of it means
     anything here, and quoting it made the app rewrite a file it had only
     opened. What must never go bare is what the reader acts on: a colon, a
     hash, a bracket, a quote, a backslash, or a leading dash. */
  const safe = /^[A-Za-z0-9][A-Za-z0-9 _.,;!?()$%&+*=<>|^~'\u00C0-\u017F/@-]*$/
  if (safe.test(text) && !reserved.test(text) && !text.endsWith(' ')) return text
  const escaped = text.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')
  return `"${escaped}"`
}

const SLUG = /^[A-Za-z0-9][A-Za-z0-9-]*$/

/** Flow lists split naively on commas, so only slugs may ride in one. */
function slugList(name: string, values: readonly string[]): string {
  const broken = values.find((v) => !SLUG.test(v))
  if (broken !== undefined) throw new Error(`${name} holds "${broken}", which is not a slug`)
  return `[${values.join(', ')}]`
}

export function serializeBoard(board: Board): string {
  const lines: string[] = []
  lines.push('version: 1')
  lines.push(`columns: ${slugList('columns', board.columns)}`)
  lines.push('items:')
  for (const item of board.items) lines.push(...serializeItem(item))
  return lines.join('\n') + '\n'
}

function serializeItem(item: BoardItem): string[] {
  const lines: string[] = []
  lines.push(`  - key: ${scalar(item.key)}`)
  lines.push(`    title: ${scalar(item.title)}`)
  lines.push(`    column: ${item.column}`)
  lines.push(`    origin: ${item.origin}`)
  if (item.foundIn !== undefined) lines.push(`    foundIn: ${scalar(item.foundIn)}`)
  if (item.blockedBy !== undefined && item.blockedBy.length > 0) {
    lines.push(`    blockedBy: ${slugList('blockedBy', item.blockedBy)}`)
  }
  if (item.epic !== undefined) lines.push(`    epic: ${scalar(item.epic)}`)
  if (item.feature !== undefined) lines.push(`    feature: ${scalar(item.feature)}`)
  if (item.sprint !== undefined) lines.push(`    sprint: ${scalar(item.sprint)}`)
  if (item.workflow !== undefined) lines.push(`    workflow: ${scalar(item.workflow)}`)
  if (item.auto !== undefined) lines.push(`    auto: ${item.auto}`)
  if (item.archived !== undefined) lines.push(`    archived: ${item.archived}`)
  lines.push(`    labels: ${slugList('labels', item.labels)}`)
  lines.push(`    specs: ${slugList('specs', item.specs)}`)
  if (item.agent !== undefined) lines.push(`    agent: ${item.agent}`)
  return lines
}

/** Named targets, one per line. The name must be a slug: the reader splits on
 *  the first colon, so a name carrying one would read back as something else. */
function linkLines(links: Readonly<Record<string, string>>): string[] {
  const entries = Object.entries(links)
  if (entries.length === 0) return []
  const lines: string[] = ['links:']
  for (const [name, target] of entries) {
    if (!SLUG.test(name)) throw new Error(`link name "${name}" is not a slug`)
    lines.push(`  ${name}: ${scalar(target)}`)
  }
  return lines
}

function criteriaLines(criteria: readonly Criterion[]): string[] {
  const lines: string[] = ['criteria:']
  for (const c of criteria) {
    lines.push(`  - id: ${scalar(c.id)}`)
    lines.push(`    text: ${scalar(c.text)}`)
  }
  return lines
}

function artifactLines(artifacts: readonly IssueArtifact[]): string[] {
  const lines: string[] = ['artifacts:']
  for (const a of artifacts) {
    lines.push(`  - name: ${scalar(a.name)}`)
    lines.push(`    rel: ${scalar(a.rel)}`)
    if (a.producedBy !== undefined) lines.push(`    producedBy: ${a.producedBy}`)
  }
  return lines
}

function taskLines(tasks: readonly Task[]): string[] {
  const lines: string[] = ['tasks:']
  for (const task of tasks) {
    lines.push(`  - id: ${scalar(task.id)}`)
    lines.push(`    text: ${scalar(task.text)}`)
    lines.push(`    done: ${task.done}`)
    /* Both absent by default. A spec that never named a criterion must not
       gain a line because the app opened it. */
    if (task.ac !== undefined && task.ac.length > 0) {
      lines.push(`    ac: ${slugList('ac', task.ac)}`)
    }
    if (task.optional === true) lines.push('    optional: true')
  }
  return lines
}

/** What the agent reads on the line it is about to work. The trailing marks
 *  are the typed fields spelled out, so the body and the frontmatter say the
 *  same thing and neither has to be trusted over the other. */
function taskLine(task: Task): string {
  const marks: string[] = []
  if (task.ac !== undefined && task.ac.length > 0) marks.push(`AC: ${task.ac.join(', ')}`)
  if (task.optional === true) marks.push('optional')
  return marks.length === 0 ? task.text : `${task.text} (${marks.join('; ')})`
}

/** The markdown mirror of the typed sections: what the agent and Claude Code
 *  read. Generated from the frontmatter, never the other way round. */
function issueBody(issue: Issue): string {
  const parts: string[] = []
  if (issue.context.trim() !== '') parts.push('## Context', '', issue.context.trim())
  if (issue.criteria.length > 0) {
    parts.push('## Acceptance Criteria', '')
    issue.criteria.forEach((c, i) => parts.push(`${i + 1}. ${c.text}`))
  }
  return parts.join('\n')
}

function specBody(spec: Spec): string {
  const parts: string[] = []
  if (spec.story.trim() !== '') parts.push('## Story', '', spec.story.trim())
  if (spec.criteria.length > 0) {
    parts.push('', '## Acceptance Criteria', '')
    spec.criteria.forEach((c, i) => parts.push(`${i + 1}. ${c.text}`))
  }
  if (spec.tasks.length > 0) {
    parts.push('', '## Tasks / Subtasks', '')
    for (const t of spec.tasks) parts.push(`- [${t.done ? 'x' : ' '}] ${taskLine(t)}`)
  }
  return parts.join('\n')
}

export function serializeIssue(issue: Issue): string {
  const lines: string[] = ['---']
  lines.push(`key: ${scalar(issue.key)}`)
  lines.push(`title: ${scalar(issue.title)}`)
  lines.push(`column: ${issue.column}`)
  lines.push(`origin: ${issue.origin}`)
  if (issue.foundIn !== undefined) lines.push(`foundIn: ${scalar(issue.foundIn)}`)
  if (issue.blockedBy !== undefined && issue.blockedBy.length > 0) {
    lines.push(`blockedBy: ${slugList('blockedBy', issue.blockedBy)}`)
  }
  if (issue.epic !== undefined) lines.push(`epic: ${scalar(issue.epic)}`)
  if (issue.feature !== undefined) lines.push(`feature: ${scalar(issue.feature)}`)
  if (issue.sprint !== undefined) lines.push(`sprint: ${scalar(issue.sprint)}`)
  if (issue.workflow !== undefined) lines.push(`workflow: ${scalar(issue.workflow)}`)
  if (issue.routeTo !== undefined) lines.push(`routeTo: ${scalar(issue.routeTo)}`)
  if (issue.routeWhy !== undefined) lines.push(`routeWhy: ${scalar(issue.routeWhy)}`)
  if (issue.auto !== undefined) lines.push(`auto: ${issue.auto}`)
  if (issue.archived !== undefined) lines.push(`archived: ${issue.archived}`)
  lines.push(`labels: ${slugList('labels', issue.labels)}`)
  lines.push(`specs: ${slugList('specs', issue.specs)}`)
  if (issue.context.trim() !== '') lines.push(`context: ${scalar(issue.context)}`)
  if (issue.criteria.length > 0) lines.push(...criteriaLines(issue.criteria))
  if (issue.artifacts.length > 0) lines.push(...artifactLines(issue.artifacts))
  lines.push(...linkLines(issue.links))
  if (issue.comments.length > 0) {
    lines.push('comments:')
    for (const comment of issue.comments) lines.push(...serializeComment(comment))
  }
  lines.push('---')
  lines.push('')
  const body = issueBody(issue)
  if (body !== '') {
    lines.push(body)
    lines.push('')
  }
  return lines.join('\n')
}

export function serializeSpec(spec: Spec): string {
  const lines: string[] = ['---']
  lines.push(`key: ${scalar(spec.key)}`)
  lines.push(`title: ${scalar(spec.title)}`)
  lines.push(`issue: ${scalar(spec.issue)}`)
  lines.push(`done: ${spec.done}`)
  if (spec.route !== undefined) lines.push(`route: ${spec.route}`)
  if (spec.story.trim() !== '') lines.push(`story: ${scalar(spec.story)}`)
  if (spec.criteria.length > 0) lines.push(...criteriaLines(spec.criteria))
  if (spec.tasks.length > 0) lines.push(...taskLines(spec.tasks))
  lines.push(...linkLines(spec.links))
  lines.push('---')
  lines.push('')
  const body = specBody(spec)
  if (body !== '') {
    lines.push(body)
    lines.push('')
  }
  return lines.join('\n')
}

function serializeComment(comment: Comment): string[] {
  return [
    `  - who: ${scalar(comment.who)}`,
    `    at: ${comment.at}`,
    `    text: ${scalar(comment.text)}`,
  ]
}
