/**
 * Splits a `.md` file into frontmatter and body, and reads issues and specs
 * out of it. The frontmatter is the structured half the screens consume; the
 * body is prose and is never parsed.
 */

import { COLUMNS, ISSUE_KEY, ORIGINS, ROUTES } from './types'
import type { Column, Comment, Defect, Issue, IssueArtifact, Origin, Parsed, Refused, Spec, Task } from './types'
import { parseYamlish } from './yamlish'
import type { Node } from './yamlish'

interface Split {
  readonly frontmatter: string
  /** 1-based line where the frontmatter starts, for defect positions. */
  readonly offset: number
  readonly body: string
}

export function splitFrontmatter(source: string, path: string): { ok: true; value: Split } | Refused {
  const lines = source.split('\n')
  if (lines[0]?.trim() !== '---') {
    return {
      ok: false,
      defects: [{ path, line: 1, message: 'file must start with a "---" frontmatter fence' }],
    }
  }
  const end = lines.findIndex((l, i) => i > 0 && l.trim() === '---')
  if (end === -1) {
    return {
      ok: false,
      defects: [{ path, line: 1, message: 'frontmatter fence "---" is never closed' }],
    }
  }
  return {
    ok: true,
    value: {
      frontmatter: lines.slice(1, end).join('\n'),
      offset: 2,
      body: lines.slice(end + 1).join('\n').trim(),
    },
  }
}

/**
 * What COULD be read of an issue, beside what could not. Never a substitute
 * for `parseIssue`: a partial value must not reach a writer, or the fields
 * that failed would be serialized away as absent.
 */
export interface PartialIssue {
  readonly issue: Issue
  /** Why it is partial, in the parser's own words, for the screen to name. */
  readonly why: readonly string[]
}

/**
 * The issue a damaged file still yields, or null when not even identity is
 * readable. Identity is the floor: a file whose key, title, column or origin
 * cannot be read has no card to hang the rest on, and guessing one would put a
 * card on the board that names nothing.
 */
export function salvageIssue(source: string, path: string): PartialIssue | null {
  const parsed = parseIssue(source, path, true)
  if (parsed.ok) return { issue: parsed.value, why: [] }
  return parsed.salvaged === undefined
    ? null
    : { issue: parsed.salvaged, why: parsed.defects.map((d) => d.message) }
}

/** The unclosed-fence case, read to the first `##` heading. A heading at column
 *  zero cannot be a YAML key, so where the frontmatter was meant to end is
 *  provable rather than guessed, and the body below it stays the body. */
function fenceless(source: string, path: string): { ok: true; value: Split } | Refused {
  const lines = source.split('\n')
  const at = lines.findIndex((l, i) => i > 0 && /^#{1,6}\s/.test(l))
  if (at === -1) {
    return { ok: false, defects: [{ path, line: 1, message: 'frontmatter fence "---" is never closed' }] }
  }
  return {
    ok: true,
    value: { frontmatter: lines.slice(1, at).join('\n'), offset: 2, body: lines.slice(at).join('\n').trim() },
  }
}

export function parseIssue(source: string, path: string, salvage = false): Parsed<Issue> {
  let split = splitFrontmatter(source, path)
  /* A file with an opening fence and no closing one is read to its first
     heading ONLY when salvaging: the strict parse still refuses it, so no
     writer ever sees a file this recovered. */
  const recovered: Defect[] = []
  if (!split.ok && salvage && source.split('\n')[0]?.trim() === '---') {
    const loose = fenceless(source, path)
    if (loose.ok) recovered.push(...split.defects)
    split = loose
  }
  if (!split.ok) return split

  const { value, defects } = parseYamlish(split.value.frontmatter, path)
  const out: Defect[] = defects.map((d) => ({ ...d, line: d.line + split.value.offset - 1 }))
  const at = (message: string) => out.push({ path, line: 0, message })
  /* The salvage pass re-reads fields the strict pass already complained about,
     so its complaints are dropped rather than counted twice. */
  const noted = () => undefined

  const key = requiredString(value.key, 'key', at)
  const title = requiredString(value.title, 'title', at)

  let column: Column | null = null
  if (typeof value.column === 'string' && (COLUMNS as readonly string[]).includes(value.column)) {
    column = value.column as Column
  } else {
    at(`column must be one of ${COLUMNS.join(', ')}, got ${JSON.stringify(value.column)}`)
  }

  let origin: Origin | null = null
  if (typeof value.origin === 'string' && (ORIGINS as readonly string[]).includes(value.origin)) {
    origin = value.origin as Origin
  } else {
    at(`origin must be one of ${ORIGINS.join(', ')}, got ${JSON.stringify(value.origin)}`)
  }

  /* A workflow is a reference to project data, not a member of a fixed set:
     an issue naming one that was deleted parses clean and resolves to none. */
  const workflow = optional(value.workflow, 'workflow', at)

  let auto: Issue['auto']
  if (value.auto !== undefined && value.auto !== null) {
    if (typeof value.auto === 'boolean') auto = value.auto
    else at(`auto must be true or false, got ${JSON.stringify(value.auto)}`)
  }

  let archived: Issue['archived']
  if (value.archived !== undefined && value.archived !== null) {
    if (typeof value.archived === 'boolean') archived = value.archived
    else at(`archived must be true or false, got ${JSON.stringify(value.archived)}`)
  }

  /* The route a stage decided on. A column that does not exist is refused
     here rather than moving a card somewhere the board has no lane for. */
  let routeTo: Issue['routeTo']
  if (value.routeTo !== undefined && value.routeTo !== null && value.routeTo !== '') {
    if (typeof value.routeTo === 'string' && (COLUMNS as readonly string[]).includes(value.routeTo)) {
      routeTo = value.routeTo as Column
    } else {
      at(`routeTo must be one of ${COLUMNS.join(', ')}, got ${JSON.stringify(value.routeTo)}`)
    }
  }

  const comments = readComments(value.comments, at)
  const criteria = readCriteria(value.criteria, at)
  const artifacts = readArtifacts(value.artifacts, at)
  const links = readLinks(value.links, at)
  const context = optional(value.context, 'context', at) ?? ''
  const foundIn = optional(value.foundIn, 'foundIn', at)
  if (foundIn !== undefined && !ISSUE_KEY.test(foundIn)) at(`foundIn must match ${ISSUE_KEY}, got ${JSON.stringify(foundIn)}`)
  /* Shape only. A blocker that does not exist, is archived, or closes a loop
     parses clean and is reported on screen; see BoardItem.blockedBy. */
  const blockedBy = optionalKeyList(value.blockedBy, 'blockedBy', at)

  /* A file read only by recovering its fence is NOT whole, however cleanly the
     rest parsed: it is returned as a refusal carrying everything it yielded, so
     the screen says what is wrong and no writer treats it as sound. */
  if (out.length > 0 || recovered.length > 0 || key === null || title === null || column === null || origin === null) {
    /* Identity is the floor. Below it there is no card, so nothing is salvaged
       and the file stays damaged exactly as it always did. */
    if (!salvage || key === null || title === null || column === null || origin === null) {
      return { ok: false, defects: [...recovered, ...out] }
    }
    return {
      ok: false,
      defects: [...recovered, ...out],
      salvaged: {
        key,
        title,
        column,
        origin,
        foundIn,
        blockedBy,
        epic: optional(value.epic, 'epic', noted),
        feature: optional(value.feature, 'feature', noted),
        sprint: optional(value.sprint, 'sprint', noted),
        workflow,
        auto,
        archived,
        routeTo,
        routeWhy: optional(value.routeWhy, 'routeWhy', noted),
        labels: strings(value.labels, 'labels', noted),
        specs: strings(value.specs, 'specs', noted),
        context,
        criteria,
        comments,
        artifacts,
        links,
      },
    }
  }

  return {
    ok: true,
    value: {
      key,
      title,
      column,
      origin,
      foundIn,
      blockedBy,
      epic: optional(value.epic, 'epic', at),
      feature: optional(value.feature, 'feature', at),
      sprint: optional(value.sprint, 'sprint', at),
      workflow,
      auto,
      archived,
      routeTo,
      routeWhy: optional(value.routeWhy, 'routeWhy', at),
      labels: strings(value.labels, 'labels', at),
      specs: strings(value.specs, 'specs', at),
      context,
      criteria,
      comments,
      artifacts,
      links,
    },
  }
}

export function parseSpec(source: string, path: string): Parsed<Spec> {
  const split = splitFrontmatter(source, path)
  if (!split.ok) return split

  const { value, defects } = parseYamlish(split.value.frontmatter, path)
  const out: Defect[] = defects.map((d) => ({ ...d, line: d.line + split.value.offset - 1 }))
  const at = (message: string) => out.push({ path, line: 0, message })

  const key = requiredString(value.key, 'key', at)
  const title = requiredString(value.title, 'title', at)
  const issue = requiredString(value.issue, 'issue', at)
  const done = value.done === true
  if (value.done !== undefined && typeof value.done !== 'boolean') {
    at(`done must be true or false, got ${JSON.stringify(value.done)}`)
  }

  let route: Spec['route']
  if (value.route !== undefined && value.route !== null && value.route !== '') {
    if (typeof value.route === 'string' && (ROUTES as readonly string[]).includes(value.route)) {
      route = value.route as Spec['route']
    } else {
      at(`route must be one of ${ROUTES.join(', ')}, got ${JSON.stringify(value.route)}`)
    }
  }

  const tasks = readTasks(value.tasks, at)
  const links = readLinks(value.links, at)
  const criteria = readCriteria(value.criteria, at)
  const story = optional(value.story, 'story', at) ?? ''

  if (out.length > 0 || key === null || title === null || issue === null) {
    return { ok: false, defects: out }
  }

  return { ok: true, value: { key, title, issue, done, route, story, criteria, tasks, links } }
}

/** Criteria accept two shapes so hand-written files stay easy: a bare list of
 *  strings, or a list of {id, text} maps. Ids are assigned when missing. */
function readCriteria(node: Node | undefined, at: (m: string) => void): { id: string; text: string }[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at('criteria must be a list')
    return []
  }
  const out: { id: string; text: string }[] = []
  node.forEach((entry, i) => {
    if (typeof entry === 'string') {
      out.push({ id: `c${i + 1}`, text: entry })
      return
    }
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      at(`criteria[${i}] must be a string or a map`)
      return
    }
    const text = entry.text
    if (typeof text !== 'string' || text === '') {
      at(`criteria[${i}] needs a non-empty text`)
      return
    }
    const id = typeof entry.id === 'string' && entry.id !== '' ? entry.id : `c${i + 1}`
    out.push({ id, text })
  })
  return out
}

function readComments(node: Node | undefined, at: (m: string) => void): Comment[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at('comments must be a list')
    return []
  }
  const out: Comment[] = []
  node.forEach((entry, i) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      at(`comments[${i}] must be a map`)
      return
    }
    const who = entry.who
    const when = entry.at
    const text = entry.text
    if (typeof who !== 'string' || typeof when !== 'string' || typeof text !== 'string') {
      at(`comments[${i}] needs string "who", "at" and "text"`)
      return
    }
    if (Number.isNaN(Date.parse(when))) {
      at(`comments[${i}].at is not a date: ${JSON.stringify(when)}`)
      return
    }
    out.push({ who, at: when, text })
  })
  return out
}

/** The one shape the viewer will open: under `.nexus/assets/`, a plain name,
 *  and `.html`. Refused here as well as in Rust, so a hand-edited issue cannot
 *  point the panel at a file outside the project. */
const ARTIFACT_REL = /^\.nexus\/assets\/[A-Za-z0-9][A-Za-z0-9._-]*\.html$/

/** Exported so a feature's doc reads the same shape the issue does. A mock is
 *  one concept with two hosts, and a second parser is how the two would come to
 *  disagree about what `.nexus/assets/` means. */
export function readArtifacts(node: Node | undefined, at: (m: string) => void): IssueArtifact[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at('artifacts must be a list')
    return []
  }
  const out: IssueArtifact[] = []
  const seen = new Set<string>()
  node.forEach((entry, i) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      at(`artifacts[${i}] must be a map`)
      return
    }
    const name = entry.name
    const rel = entry.rel
    if (typeof name !== 'string' || name === '' || typeof rel !== 'string') {
      at(`artifacts[${i}] needs non-empty string "name" and "rel"`)
      return
    }
    if (rel.includes('..') || !ARTIFACT_REL.test(rel)) {
      at(`artifacts[${i}].rel must be a .html file under .nexus/assets/, got ${JSON.stringify(rel)}`)
      return
    }
    if (seen.has(rel)) {
      at(`artifacts[${i}] repeats rel "${rel}"`)
      return
    }
    seen.add(rel)
    let producedBy: Column | undefined
    if (entry.producedBy !== undefined && entry.producedBy !== null && entry.producedBy !== '') {
      if (typeof entry.producedBy === 'string' && (COLUMNS as readonly string[]).includes(entry.producedBy)) {
        producedBy = entry.producedBy as Column
      } else {
        at(`artifacts[${i}].producedBy must be one of ${COLUMNS.join(', ')}`)
        return
      }
    }
    out.push({ name, rel, producedBy })
  })
  return out
}

function readTasks(node: Node | undefined, at: (m: string) => void): Task[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at('tasks must be a list')
    return []
  }
  const out: Task[] = []
  const seen = new Set<string>()
  node.forEach((entry, i) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      at(`tasks[${i}] must be a map`)
      return
    }
    const id = entry.id
    const text = entry.text
    if (typeof id !== 'string' || id === '' || typeof text !== 'string' || text === '') {
      at(`tasks[${i}] needs non-empty string "id" and "text"`)
      return
    }
    if (seen.has(id)) {
      at(`tasks[${i}] repeats id "${id}"`)
      return
    }
    seen.add(id)
    const ac = readBacklinks(entry.ac, i, at)
    let optional: boolean | undefined
    if (entry.optional !== undefined && entry.optional !== null) {
      if (typeof entry.optional !== 'boolean') {
        at(`tasks[${i}].optional must be true or false, got ${JSON.stringify(entry.optional)}`)
        return
      }
      optional = entry.optional === true ? true : undefined
    }
    out.push({ id, text, done: entry.done === true, ac, optional })
  })
  return out
}

/**
 * A task's criterion ids. Refused unless every entry is a slug: the writer
 * emits them in a flow list, so an id carrying a comma or a colon would give
 * a file the app can open and can never save.
 */
function readBacklinks(node: Node | undefined, i: number, at: (m: string) => void): string[] | undefined {
  if (node === undefined || node === null) return undefined
  if (!Array.isArray(node)) {
    at(`tasks[${i}].ac must be a list of criterion ids`)
    return undefined
  }
  const out: string[] = []
  for (const entry of node) {
    if (typeof entry !== 'string' || !BACKLINK_ID.test(entry)) {
      at(`tasks[${i}].ac holds ${JSON.stringify(entry)}, which is not a criterion id`)
      return undefined
    }
    if (out.includes(entry)) {
      at(`tasks[${i}].ac repeats "${entry}"`)
      return undefined
    }
    out.push(entry)
  }
  return out.length === 0 ? undefined : out
}

/** The same slug the writer's flow list accepts, so what parses can be saved. */
const BACKLINK_ID = /^[A-Za-z0-9][A-Za-z0-9-]*$/

/** A link name is a slug because the writer refuses anything else: a name that
 *  parses and cannot be written back is a file the app can open and not save. */
const LINK_NAME = /^[A-Za-z0-9][A-Za-z0-9-]*$/

function readLinks(node: Node | undefined, at: (m: string) => void): Record<string, string> {
  if (node === undefined || node === null) return {}
  if (node === null || typeof node !== 'object' || Array.isArray(node)) {
    at('links must be a map')
    return {}
  }
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(node)) {
    if (!LINK_NAME.test(k)) {
      at(`links.${k} is not a slug, so it could never be written back`)
      continue
    }
    if (typeof v !== 'string') {
      at(`links.${k} must be a string`)
      continue
    }
    out[k] = v
  }
  return out
}

function requiredString(node: Node | undefined, name: string, at: (m: string) => void): string | null {
  if (typeof node !== 'string' || node.trim() === '') {
    at(`${name} must be a non-empty string, got ${JSON.stringify(node)}`)
    return null
  }
  return node.trim()
}

function optional(node: Node | undefined, name: string, at: (m: string) => void): string | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node !== 'string') {
    at(`${name} must be a string, got ${JSON.stringify(node)}`)
    return undefined
  }
  return node
}

/** A list of issue keys, absent when empty so a file that never named one
 *  round-trips without gaining a line. */
function optionalKeyList(
  node: Node | undefined,
  name: string,
  at: (m: string) => void,
): string[] | undefined {
  if (node === undefined || node === null) return undefined
  if (!Array.isArray(node)) {
    at(`${name} must be a list`)
    return undefined
  }
  const out: string[] = []
  node.forEach((entry, i) => {
    if (typeof entry !== 'string' || !ISSUE_KEY.test(entry)) {
      at(`${name}[${i}] must match ${ISSUE_KEY}, got ${JSON.stringify(entry)}`)
      return
    }
    out.push(entry)
  })
  return out.length === 0 ? undefined : out
}

function strings(node: Node | undefined, name: string, at: (m: string) => void): string[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at(`${name} must be a list`)
    return []
  }
  const out: string[] = []
  node.forEach((entry, i) => {
    if (typeof entry !== 'string') at(`${name}[${i}] must be a string`)
    else out.push(entry)
  })
  return out
}
