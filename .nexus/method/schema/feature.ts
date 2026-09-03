/**
 * Reads and writes a feature's `feature.yaml` and a sprint's
 * `sprints/<key>.yaml`. Both are app-written and small: a feature records which
 * of its five docs exist and which issues it originated; a sprint records a
 * timebox and its members. The doc bodies live beside `feature.yaml` as the
 * five markdown files, parsed by their own kind, never here.
 */

import { AGENTS, COLUMNS, DOC_KINDS, ENGINES, ENGINE_MODELS, EXITS, LEGACY_CODEX_MODELS, NOTIFY_FIELDS, ORIGINS, STORED_MODELS, TIERS, VOICES, isSafeRef } from './types'
import type { AgentConfig, AgentId, Column, Defect, DocKind, DocState, EngineId, Epic, Epics, Feature, Model, NotifyConfig, Origin, Parsed, Project, Sprint, Story, Tier, Voice, Workflow } from './types'
import { parseYamlish } from './yamlish'
import type { Node } from './yamlish'
import { RETIRED } from './board'
import { scalar } from './serialize'
import { splitFrontmatter } from './frontmatter'

const KEY = /^[a-z0-9][a-z0-9-]*$/i
const FEATURE_STATUS = ['planning', 'shipped', 'archived'] as const
const DOC_STATES = ['empty', 'draft', 'done'] as const

export function parseFeature(source: string, path: string): Parsed<Feature> {
  const { value, defects } = parseYamlish(source, path)
  const out: Defect[] = [...defects]
  const at = (message: string) => out.push({ path, line: 0, message })

  const key = requiredKey(value.key, 'key', at)
  const name = requiredString(value.name, 'name', at)

  let status: Feature['status'] = 'planning'
  if (value.status !== undefined) {
    if (typeof value.status === 'string' && (FEATURE_STATUS as readonly string[]).includes(value.status)) {
      status = value.status as Feature['status']
    } else {
      at(`status must be one of ${FEATURE_STATUS.join(', ')}, got ${JSON.stringify(value.status)}`)
    }
  }

  const docs = readDocs(value.docs, at)
  const issues = stringList(value.issues, 'issues', at)

  if (out.length > 0 || key === null || name === null) return { ok: false, defects: out }
  return { ok: true, value: { key, name, status, docs, issues } }
}

function readDocs(node: Node | undefined, at: (m: string) => void): Record<DocKind, DocState> {
  const docs: Record<DocKind, DocState> = {
    brief: 'empty',
    prd: 'empty',
    ux: 'empty',
    architecture: 'empty',
    epics: 'empty',
  }
  if (node === undefined || node === null) return docs
  if (typeof node !== 'object' || Array.isArray(node)) {
    at('docs must be a map of kind to state')
    return docs
  }
  for (const [k, v] of Object.entries(node)) {
    if (!(DOC_KINDS as readonly string[]).includes(k)) {
      at(`docs has unknown kind "${k}"`)
      continue
    }
    if (typeof v !== 'string' || !(DOC_STATES as readonly string[]).includes(v)) {
      at(`docs.${k} must be one of ${DOC_STATES.join(', ')}, got ${JSON.stringify(v)}`)
      continue
    }
    docs[k as DocKind] = v as DocState
  }
  return docs
}

export function serializeFeature(feature: Feature): string {
  const lines: string[] = []
  lines.push(`key: ${scalar(feature.key)}`)
  lines.push(`name: ${scalar(feature.name)}`)
  lines.push(`status: ${feature.status}`)
  lines.push('docs:')
  for (const kind of DOC_KINDS) lines.push(`  ${kind}: ${feature.docs[kind]}`)
  lines.push(`issues: [${feature.issues.join(', ')}]`)
  return lines.join('\n') + '\n'
}

export function parseSprint(source: string, path: string): Parsed<Sprint> {
  const { value, defects } = parseYamlish(source, path)
  const out: Defect[] = [...defects]
  const at = (message: string) => out.push({ path, line: 0, message })

  const key = requiredKey(value.key, 'key', at)
  const name = requiredString(value.name, 'name', at)
  const starts = optionalDate(value.starts, 'starts', at)
  const ends = optionalDate(value.ends, 'ends', at)
  const issues = stringList(value.issues, 'issues', at)
  const loop = optionalChoice(value.loop, 'loop', ['to-review', 'full-cycle'] as const, at)
  const loopLimit = optionalWhole(value.loopLimit, 'loopLimit', 1, 4, at)
  const loopFailures = optionalWhole(value.loopFailures, 'loopFailures', 0, 2, at)
  const loopReconciled = optionalList(value.loopReconciled, 'loopReconciled', at)
  const loopLedger = optionalList(value.loopLedger, 'loopLedger', at)

  if (out.length > 0 || key === null || name === null) return { ok: false, defects: out }
  return { ok: true, value: { key, name, starts, ends, issues, loop, loopLimit, loopFailures, loopReconciled, loopLedger } }
}

export function serializeSprint(sprint: Sprint): string {
  const lines: string[] = []
  lines.push(`key: ${scalar(sprint.key)}`)
  lines.push(`name: ${scalar(sprint.name)}`)
  if (sprint.starts !== undefined) lines.push(`starts: ${sprint.starts}`)
  if (sprint.ends !== undefined) lines.push(`ends: ${sprint.ends}`)
  lines.push(`issues: [${sprint.issues.join(', ')}]`)
  if (sprint.loop !== undefined) lines.push(`loop: ${sprint.loop}`)
  if (sprint.loopLimit !== undefined) lines.push(`loopLimit: ${sprint.loopLimit}`)
  if (sprint.loopFailures !== undefined) lines.push(`loopFailures: ${sprint.loopFailures}`)
  if (sprint.loopReconciled !== undefined) lines.push(`loopReconciled: [${sprint.loopReconciled.map(scalar).join(', ')}]`)
  if (sprint.loopLedger !== undefined) lines.push(`loopLedger: [${sprint.loopLedger.map(scalar).join(', ')}]`)
  return lines.join('\n') + '\n'
}

function optionalChoice<T extends string>(
  node: Node | undefined,
  name: string,
  choices: readonly T[],
  at: (m: string) => void,
): T | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node === 'string' && choices.includes(node as T)) return node as T
  at(`${name} must be one of ${choices.join(', ')}, got ${JSON.stringify(node)}`)
  return undefined
}

function optionalWhole(
  node: Node | undefined,
  name: string,
  least: number,
  most: number,
  at: (m: string) => void,
): number | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node === 'number' && Number.isInteger(node) && node >= least && node <= most) return node
  at(`${name} must be a whole number from ${least} through ${most}, got ${JSON.stringify(node)}`)
  return undefined
}

function optionalList(node: Node | undefined, name: string, at: (m: string) => void): string[] | undefined {
  if (node === undefined || node === null) return undefined
  const read = stringList(node, name, at)
  return read.length === 0 ? undefined : read
}

/**
 * Reads `.nexus/workflows.yaml`: the workflows this project authored. Columns
 * and origin are checked against the method here; that the steps form an
 * unbroken chain is checked in src/lib/workflows.ts, which owns the stage table.
 */
export function parseWorkflows(source: string, path: string): Parsed<Workflow[]> {
  const { value, defects } = parseYamlish(source, path)
  const out: Defect[] = [...defects]
  const at = (message: string) => out.push({ path, line: 0, message })

  if (value.version !== 1) at(`version must be 1, got ${JSON.stringify(value.version)}`)

  const workflows: Workflow[] = []
  const node = value.workflows
  if (node !== undefined && node !== null) {
    if (!Array.isArray(node)) at('workflows must be a list')
    else {
      const seen = new Set<string>()
      node.forEach((entry, i) => {
        if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
          at(`workflows[${i}] must be a map`)
          return
        }
        const workflow = readWorkflow(entry, i, at)
        if (workflow === null) return
        if (seen.has(workflow.id)) at(`workflows[${i}] repeats id "${workflow.id}"`)
        seen.add(workflow.id)
        workflows.push(workflow)
      })
    }
  }

  if (out.length > 0) return { ok: false, defects: out }
  return { ok: true, value: workflows }
}

function readWorkflow(
  entry: { [key: string]: Node },
  i: number,
  at: (m: string) => void,
): Workflow | null {
  const where = (m: string) => at(`workflows[${i}]: ${m}`)
  const id = requiredKey(entry.id, 'id', where)
  const name = requiredString(entry.name, 'name', where)
  const summary = typeof entry.summary === 'string' ? entry.summary : ''

  let origin: Origin | null = null
  if (typeof entry.origin === 'string' && (ORIGINS as readonly string[]).includes(entry.origin)) {
    origin = entry.origin as Origin
  } else {
    where(`origin must be one of ${ORIGINS.join(', ')}, got ${JSON.stringify(entry.origin)}`)
  }

  const steps = columnList(entry.steps, 'steps', where)
  const stops = columnList(entry.stops, 'stops', where)
  /* A stop outside the path would never be reached, so it is a defect rather
     than a line that quietly does nothing. */
  for (const stop of stops) {
    if (!steps.includes(stop)) where(`stops names "${stop}", which is not one of its steps`)
  }

  if (id === null || name === null || origin === null) return null
  return { id, name, summary, steps, origin, stops }
}

function columnList(node: Node | undefined, name: string, at: (m: string) => void): Column[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at(`${name} must be a list`)
    return []
  }
  const out: Column[] = []
  node.forEach((entry, i) => {
    /* A RETIRED column is migrated here exactly as the board migrates it. A
       workflow naming one refused the whole file, which left the person told
       to fix it in an editor by the very screen that edits it. */
    const named = typeof entry === 'string' && entry in RETIRED ? RETIRED[entry] : entry
    if (typeof named !== 'string' || !(COLUMNS as readonly string[]).includes(named)) {
      at(`${name}[${i}] must be a column, got ${JSON.stringify(entry)}`)
      return
    }
    /* Migrating a step onto one the workflow already lists would make the
       chain visit it twice, so the duplicate is dropped rather than kept. */
    if (!out.includes(named as Column)) out.push(named as Column)
  })
  return out
}

export function serializeWorkflows(workflows: readonly Workflow[]): string {
  const lines: string[] = ['version: 1', 'workflows:']
  for (const workflow of workflows) {
    lines.push(`  - id: ${scalar(workflow.id)}`)
    lines.push(`    name: ${scalar(workflow.name)}`)
    if (workflow.summary.trim() !== '') lines.push(`    summary: ${scalar(workflow.summary)}`)
    lines.push(`    steps: [${workflow.steps.join(', ')}]`)
    lines.push(`    origin: ${workflow.origin}`)
    lines.push(`    stops: [${workflow.stops.join(', ')}]`)
  }
  return lines.join('\n') + '\n'
}

function requiredKey(node: Node | undefined, name: string, at: (m: string) => void): string | null {
  if (typeof node !== 'string' || !KEY.test(node)) {
    at(`${name} must match ${KEY}, got ${JSON.stringify(node)}`)
    return null
  }
  return node
}

function requiredString(node: Node | undefined, name: string, at: (m: string) => void): string | null {
  if (typeof node !== 'string' || node.trim() === '') {
    at(`${name} must be a non-empty string, got ${JSON.stringify(node)}`)
    return null
  }
  return node.trim()
}

function optionalDate(node: Node | undefined, name: string, at: (m: string) => void): string | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node !== 'string' || Number.isNaN(Date.parse(node))) {
    at(`${name} must be a date, got ${JSON.stringify(node)}`)
    return undefined
  }
  return node
}

function stringList(node: Node | undefined, name: string, at: (m: string) => void): string[] {
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

const SKILLS = ['beginner', 'intermediate', 'expert'] as const
const PERMISSIONS = ['edits', 'manual', 'bypass'] as const
/** Exported so the machine defaults validate an editor against the same list
 *  a project.yaml is validated against, rather than a second copy that drifts. */
export const EDITORS = ['vscode', 'cursor', 'windsurf', 'zed'] as const
const EXIT_NAMES: readonly string[] = EXITS

/** Per-agent settings, keyed by agent id. An unknown id, model or voice is a
 *  defect rather than a silent drop: a typo here changes how work runs. */
function readAgents(
  node: Node | undefined,
  at: (m: string) => void,
): Project['agents'] | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node !== 'object' || Array.isArray(node)) {
    at('agents must be a map of agent id to its settings')
    return undefined
  }
  const out: Partial<Record<AgentId, AgentConfig>> = {}
  for (const [id, value] of Object.entries(node)) {
    if (!(AGENTS as readonly string[]).includes(id)) {
      at(`agents has no such agent: ${id}`)
      continue
    }
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      at(`agents.${id} must be a map`)
      continue
    }
    const config: { model?: Model; voice?: Voice; engine?: EngineId; tier?: Tier } = {}
    const engine = readEngine(value.engine, `agents.${id}.engine`, at)
    if (engine !== undefined) config.engine = engine
    const model = value.model
    if (model !== undefined && model !== null) {
      const offered = engine === undefined ? STORED_MODELS : ENGINE_MODELS[engine]
      const preservedLegacy = typeof model === 'string'
        && engine === 'codex'
        && (LEGACY_CODEX_MODELS as readonly string[]).includes(model)
      if (typeof model === 'string' && ((offered as readonly string[]).includes(model) || preservedLegacy)) {
        config.model = model as Model
      } else {
        const owner = engine === undefined ? 'the configured engine' : engine
        at(`agents.${id}.model must be one of ${offered.join(', ')} for ${owner}, got ${JSON.stringify(model)}`)
      }
    }
    const voice = value.voice
    if (voice !== undefined && voice !== null) {
      if (typeof voice === 'string' && (VOICES as readonly string[]).includes(voice)) {
        config.voice = voice as Voice
      } else {
        at(`agents.${id}.voice must be one of ${VOICES.join(', ')}, got ${JSON.stringify(voice)}`)
      }
    }
    const tier = value.tier
    if (tier !== undefined && tier !== null) {
      if (typeof tier === 'string' && (TIERS as readonly string[]).includes(tier)) {
        config.tier = tier as Tier
      } else {
        at(`agents.${id}.tier must be one of ${TIERS.join(', ')}, got ${JSON.stringify(tier)}`)
      }
    }
    if (
      config.model !== undefined
      || config.voice !== undefined
      || config.engine !== undefined
      || config.tier !== undefined
    ) {
      out[id as AgentId] = config
    }
  }
  return Object.keys(out).length > 0 ? out : undefined
}

/** One engine id. A blank value parses as null and is absent rather than an id
 *  of `""`, so a field an editor emptied falls to the next rung instead of
 *  naming an engine nothing drives. */
function readEngine(node: Node | undefined, field: string, at: (m: string) => void): EngineId | undefined {
  if (node === undefined || node === null) return undefined
  const name = typeof node === 'string' ? node.trim() : ''
  if (!(ENGINES as readonly string[]).includes(name)) {
    at(`${field} must be one of ${ENGINES.join(', ')}, got ${JSON.stringify(node)}`)
    return undefined
  }
  return name as EngineId
}

/** The engine each column runs on. A key that is not a column is a defect and
 *  not a crash: this file is hand-editable and a typo must be named. */
function readStageEngines(
  node: Node | undefined,
  at: (m: string) => void,
): Partial<Record<Column, EngineId>> | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node !== 'object' || Array.isArray(node)) {
    at('stageEngines must be a map of column to engine')
    return undefined
  }
  const out: Partial<Record<Column, EngineId>> = {}
  for (const [column, value] of Object.entries(node)) {
    if (!(COLUMNS as readonly string[]).includes(column)) {
      at(`stageEngines has no such column: ${column}`)
      continue
    }
    const engine = readEngine(value, `stageEngines.${column}`, at)
    if (engine !== undefined) out[column as Column] = engine
  }
  return Object.keys(out).length > 0 ? out : undefined
}

/**
 * What a lane's own checkout is prepared with. `project.yaml` travels with a
 * clone, so a copy pattern that could name a file outside the project is a
 * defect here rather than a path the app resolves later: a pattern refused at
 * the call has already been read, and by then it has travelled.
 */
function readSetup(node: Node | undefined, at: (m: string) => void): Project['setup'] | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node !== 'object' || Array.isArray(node)) {
    at('setup must be a map with copy and command')
    return undefined
  }
  const map = node as Record<string, Node>
  const copy = map.copy === undefined || map.copy === null ? undefined : stringList(map.copy, 'setup.copy', at)
  for (const pattern of copy ?? []) {
    if (!safeCopyPattern(pattern)) {
      at(`setup.copy cannot name anything outside the project: ${JSON.stringify(pattern)}`)
    }
  }
  let command: string | undefined
  if (map.command !== undefined && map.command !== null) {
    if (typeof map.command !== 'string') {
      at('setup.command must be a string')
    } else if (map.command.trim() !== '') {
      command = map.command.trim()
    }
  }
  if (copy === undefined && command === undefined) return undefined
  return { copy, command }
}

/** Mirrors `safeCopyPattern` in src/lib/worktree.ts. Kept here because the
 *  schema refuses what it cannot vouch for, and the two must agree. */
function safeCopyPattern(pattern: string): boolean {
  if (pattern === '' || pattern.length > 200) return false
  if (pattern.startsWith('/') || pattern.startsWith('~')) return false
  if (pattern.split('/').some((p) => p === '..' || p === '.')) return false
  return !/[\0\n\r]/.test(pattern)
}

/** Reads `.nexus/project.yaml`: who the project is for and in which language
 *  its agents speak and write. Every field but the name is optional. */
export function parseProject(source: string, path: string): Parsed<Project> {
  const { value, defects } = parseYamlish(source, path)
  const out: Defect[] = [...defects]
  const at = (message: string) => out.push({ path, line: 0, message })

  const name = requiredString(value.name, 'name', at)

  let skill: Project['skill']
  if (value.skill !== undefined && value.skill !== null) {
    if (typeof value.skill === 'string' && (SKILLS as readonly string[]).includes(value.skill)) {
      skill = value.skill as Project['skill']
    } else {
      at(`skill must be one of ${SKILLS.join(', ')}, got ${JSON.stringify(value.skill)}`)
    }
  }

  const text = (node: Node | undefined, field: string): string | undefined => {
    if (node === undefined || node === null) return undefined
    if (typeof node !== 'string') {
      at(`${field} must be a string, got ${JSON.stringify(node)}`)
      return undefined
    }
    return node.trim() === '' ? undefined : node.trim()
  }

  let permissions: Project['permissions']
  if (value.permissions !== undefined && value.permissions !== null) {
    if (typeof value.permissions === 'string' && (PERMISSIONS as readonly string[]).includes(value.permissions)) {
      permissions = value.permissions as Project['permissions']
    } else {
      at(`permissions must be one of ${PERMISSIONS.join(', ')}, got ${JSON.stringify(value.permissions)}`)
    }
  }

  let editor: Project['editor']
  if (value.editor !== undefined && value.editor !== null) {
    if (typeof value.editor === 'string' && (EDITORS as readonly string[]).includes(value.editor)) {
      editor = value.editor as Project['editor']
    } else {
      at(`editor must be one of ${EDITORS.join(', ')}, got ${JSON.stringify(value.editor)}`)
    }
  }

  const agents = readAgents(value.agents, at)
  const notify = readNotify(value.notify, at)
  const engine = readEngine(value.engine, 'engine', at)
  const stageEngines = readStageEngines(value.stageEngines, at)
  const setup = readSetup(value.setup, at)

  /* A branch name reaches a git argv, so what git refuses is refused here
     rather than at the call, where a bad value would already have travelled. */
  const mainLine = text(value.mainLine, 'mainLine')
  if (mainLine !== undefined && !isSafeRef(mainLine)) {
    at(`mainLine is not a branch name git would accept: ${JSON.stringify(mainLine)}`)
  }

  let exit: Project['exit']
  if (value.exit !== undefined && value.exit !== null) {
    if (typeof value.exit === 'string' && EXIT_NAMES.includes(value.exit)) {
      exit = value.exit as Project['exit']
    } else {
      at(`exit must be one of ${EXITS.join(', ')}, got ${JSON.stringify(value.exit)}`)
    }
  }

  if (out.length > 0 || name === null) return { ok: false, defects: out }
  return {
    ok: true,
    value: {
      name,
      company: text(value.company, 'company'),
      user: text(value.user, 'user'),
      language: text(value.language, 'language'),
      outputLanguage: text(value.outputLanguage, 'outputLanguage'),
      skill,
      permissions,
      editor,
      mainLine,
      exit,
      setup,
      feature: text(value.feature, 'feature'),
      sprint: text(value.sprint, 'sprint'),
      notify,
      agents,
      engine,
      stageEngines,
    },
  }
}

/** Four switches, each a boolean or absent. An unknown key is REFUSED rather
 *  than ignored: a misspelt `failure:` that parses clean is a person who
 *  believes they turned something off and did not. */
function readNotify(node: Node | undefined, at: (m: string) => void): NotifyConfig | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node !== 'object' || Array.isArray(node)) {
    at('notify must be a map of switch to true or false')
    return undefined
  }
  const out: { enabled?: boolean; questions?: boolean; failures?: boolean; mute?: boolean } = {}
  for (const [key, value] of Object.entries(node)) {
    if (!(NOTIFY_FIELDS as readonly string[]).includes(key)) {
      at(`notify has no such switch: ${key}`)
      continue
    }
    if (value === null) continue
    if (typeof value !== 'boolean') {
      at(`notify.${key} must be true or false, got ${JSON.stringify(value)}`)
      continue
    }
    out[key as (typeof NOTIFY_FIELDS)[number]] = value
  }
  return Object.keys(out).length > 0 ? out : undefined
}

export function serializeProject(project: Project): string {
  const lines: string[] = [`name: ${scalar(project.name)}`]
  const put = (key: string, v: string | undefined) => {
    if (v !== undefined && v !== '') lines.push(`${key}: ${scalar(v)}`)
  }
  put('company', project.company)
  put('user', project.user)
  put('language', project.language)
  put('outputLanguage', project.outputLanguage)
  put('skill', project.skill)
  put('permissions', project.permissions)
  put('editor', project.editor)
  put('mainLine', project.mainLine)
  put('exit', project.exit)
  put('feature', project.feature)
  put('sprint', project.sprint)
  put('engine', project.engine)
  if (project.setup !== undefined) {
    lines.push('setup:')
    if (project.setup.copy !== undefined) {
      /* An empty list is written as one, because "copy nothing" and "copy the
         default" are different decisions and absence already means the second. */
      lines.push('  copy:')
      for (const pattern of project.setup.copy) lines.push(`    - ${scalar(pattern)}`)
    }
    if (project.setup.command !== undefined) lines.push(`  command: ${scalar(project.setup.command)}`)
  }
  const stages = Object.entries(project.stageEngines ?? {})
  if (stages.length > 0) {
    lines.push('stageEngines:')
    /* Written in the board's own column order, so two projects that chose the
       same engines produce the same file whatever order they were set in. */
    for (const column of COLUMNS) {
      const engine = project.stageEngines?.[column]
      if (engine !== undefined) lines.push(`  ${column}: ${engine}`)
    }
  }
  const notify = project.notify
  if (notify !== undefined) {
    const set = NOTIFY_FIELDS.filter((f) => notify[f] !== undefined)
    if (set.length > 0) {
      lines.push('notify:')
      /* Written in the declared order, so two projects that chose the same
         switches produce the same file whatever order they were set in. */
      for (const field of NOTIFY_FIELDS) {
        if (notify[field] !== undefined) lines.push(`  ${field}: ${notify[field] === true ? 'true' : 'false'}`)
      }
    }
  }
  const agents = Object.entries(project.agents ?? {})
  if (agents.length > 0) {
    lines.push('agents:')
    for (const [id, config] of agents) {
      lines.push(`  ${id}:`)
      if (config?.model !== undefined) lines.push(`    model: ${config.model}`)
      if (config?.tier !== undefined) lines.push(`    tier: ${config.tier}`)
      if (config?.voice !== undefined) lines.push(`    voice: ${config.voice}`)
      if (config?.engine !== undefined) lines.push(`    engine: ${config.engine}`)
    }
  }
  return lines.join('\n') + '\n'
}

/** Reads epics.md: frontmatter is the typed source (epics, stories, criteria),
 *  the body is a mirror the parser ignores, exactly as issue and spec do. */
export function parseEpics(source: string, path: string): Parsed<Epics> {
  const split = splitFrontmatter(source, path)
  if (!split.ok) return split

  const { value, defects } = parseYamlish(split.value.frontmatter, path)
  const out: Defect[] = defects.map((d) => ({ ...d, line: d.line + split.value.offset - 1 }))
  const at = (message: string) => out.push({ path, line: 0, message })

  const requirements = typeof value.requirements === 'string' ? value.requirements : ''
  const epics = readEpics(value.epics, at)

  if (out.length > 0) return { ok: false, defects: out }
  return { ok: true, value: { requirements, epics } }
}

function readEpics(node: Node | undefined, at: (m: string) => void): Epic[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at('epics must be a list')
    return []
  }
  const seen = new Set<string>()
  const out: Epic[] = []
  node.forEach((entry, i) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      at(`epics[${i}] must be a map`)
      return
    }
    const id = requireField(entry.id, `epics[${i}].id`, at)
    const title = requireField(entry.title, `epics[${i}].title`, at)
    if (id !== null && seen.has(id)) at(`epics[${i}] repeats id "${id}"`)
    if (id !== null) seen.add(id)
    const goal = typeof entry.goal === 'string' ? entry.goal : ''
    const stories = readStories(entry.stories, i, at)
    if (id === null || title === null) return
    out.push({ id, title, goal, stories })
  })
  return out
}

function readStories(node: Node | undefined, epicIndex: number, at: (m: string) => void): Story[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    at(`epics[${epicIndex}].stories must be a list`)
    return []
  }
  const out: Story[] = []
  node.forEach((entry, j) => {
    const where = `epics[${epicIndex}].stories[${j}]`
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      at(`${where} must be a map`)
      return
    }
    const id = requireField(entry.id, `${where}.id`, at)
    const title = requireField(entry.title, `${where}.title`, at)
    const statement = typeof entry.statement === 'string' ? entry.statement : ''
    const criteria = stringList(entry.criteria, `${where}.criteria`, at)
    const dependsOn = readDependsOn(entry.dependsOn, `${where}.dependsOn`, at)
    if (id === null || title === null) return
    out.push(dependsOn === undefined ? { id, title, statement, criteria } : { id, title, statement, criteria, dependsOn })
  })
  return out
}

/**
 * A story names the stories it waits on, never an issue key: the key is minted
 * at creation and does not exist while the doc is written. Absent stays absent
 * so a doc that declared nothing does not gain a line by being read.
 *
 * A BARE `1.10` IS REFUSED, LOUDLY. The reader hands decimals over as numbers
 * and `1.10` arrives as 1.1, which is a DIFFERENT REAL STORY: taking it would
 * write a blocker nobody asked for. Say so and name the fix instead.
 */
function readDependsOn(node: Node | undefined, name: string, at: (m: string) => void): string[] | undefined {
  if (node === undefined || node === null) return undefined
  if (!Array.isArray(node)) {
    at(`${name} must be a list`)
    return undefined
  }
  const out: string[] = []
  node.forEach((entry, i) => {
    if (typeof entry === 'number') {
      if (!Number.isInteger(entry)) {
        at(`${name}[${i}] must be quoted: ${entry} cannot be told apart from another story's id`)
        return
      }
      pushRef(out, String(entry), `${name}[${i}]`, at)
      return
    }
    if (typeof entry !== 'string') {
      at(`${name}[${i}] must be a story reference, got ${JSON.stringify(entry)}`)
      return
    }
    pushRef(out, entry.trim(), `${name}[${i}]`, at)
  })
  return out.length === 0 ? undefined : out
}

function pushRef(out: string[], written: string, where: string, at: (m: string) => void): void {
  if (written === '') at(`${where} must be a non-empty story reference`)
  else if (!out.includes(written)) out.push(written)
}

function requireField(node: Node | undefined, name: string, at: (m: string) => void): string | null {
  if (typeof node !== 'string' || node.trim() === '') {
    at(`${name} must be a non-empty string, got ${JSON.stringify(node)}`)
    return null
  }
  return node.trim()
}

/** Writes epics.md: typed frontmatter, then the method's epic breakdown as the
 *  body an agent reads. The body is generated from the frontmatter, never the
 *  reverse. */
export function serializeEpics(epics: Epics): string {
  const lines: string[] = ['---']
  if (epics.requirements.trim() !== '') lines.push(`requirements: ${scalar(epics.requirements)}`)
  if (epics.epics.length > 0) {
    lines.push('epics:')
    for (const epic of epics.epics) lines.push(...epicLines(epic))
  }
  lines.push('---', '')
  const body = epicsBody(epics)
  if (body !== '') lines.push(body, '')
  return lines.join('\n')
}

function epicLines(epic: Epic): string[] {
  const lines: string[] = []
  lines.push(`  - id: ${scalar(epic.id)}`)
  lines.push(`    title: ${scalar(epic.title)}`)
  if (epic.goal.trim() !== '') lines.push(`    goal: ${scalar(epic.goal)}`)
  if (epic.stories.length > 0) {
    lines.push('    stories:')
    for (const story of epic.stories) {
      lines.push(`      - id: ${scalar(story.id)}`)
      lines.push(`        title: ${scalar(story.title)}`)
      if (story.statement.trim() !== '') lines.push(`        statement: ${scalar(story.statement)}`)
      if (story.criteria.length > 0) {
        lines.push('        criteria:')
        for (const c of story.criteria) lines.push(`          - ${scalar(c)}`)
      }
      if (story.dependsOn !== undefined && story.dependsOn.length > 0) {
        lines.push('        dependsOn:')
        for (const d of story.dependsOn) lines.push(`          - ${scalar(d)}`)
      }
    }
  }
  return lines
}

function epicsBody(epics: Epics): string {
  const parts: string[] = []
  if (epics.requirements.trim() !== '') parts.push('## Requirements Inventory', '', epics.requirements.trim(), '')
  for (const epic of epics.epics) {
    parts.push(`## ${epic.title}`, '')
    if (epic.goal.trim() !== '') parts.push(epic.goal.trim(), '')
    for (const story of epic.stories) {
      parts.push(`### ${story.title}`, '')
      if (story.statement.trim() !== '') parts.push(story.statement.trim(), '')
      if (story.criteria.length > 0) {
        parts.push('**Acceptance Criteria:**', '')
        for (const c of story.criteria) parts.push(`- ${c}`)
        parts.push('')
      }
      if (story.dependsOn !== undefined && story.dependsOn.length > 0) {
        parts.push(`**Depends on:** ${story.dependsOn.join(', ')}`, '')
      }
    }
  }
  return parts.join('\n').trimEnd()
}

/**
 * Which stories have no issue yet. The bridge writes the story's title onto
 * the issue, so that is the match. Without this the picker offered every story
 * again on a board that already held them, and taking the offer would have
 * made a second copy of each.
 */
export function unmadeStories(
  epics: Epics,
  items: readonly { readonly title: string; readonly feature?: string }[],
  featureKey: string,
): string[] {
  const made = new Set(items.filter((i) => i.feature === featureKey).map((i) => i.title))
  return epics.epics.flatMap((epic) =>
    epic.stories.filter((s) => !made.has(s.title)).map((s) => `${epic.id}/${s.id}`),
  )
}
