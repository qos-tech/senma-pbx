/**
 * What this MACHINE knows about the person, `~/.nexus/defaults.yaml`. Four
 * answers that are about them and not about any project, so a new project
 * starts from them instead of asking again. The keys are project.yaml's own
 * keys, because a default is a starting value for that file and a second
 * spelling here would be a mapping table nobody maintains.
 */

import { EDITORS } from './feature'
import { scalar } from './serialize'
import { ENGINES, STORED_MODELS } from './types'
import { parseYamlish } from './yamlish'
import type { Defect, EngineId, Model, Parsed, Project } from './types'

export interface Defaults {
  readonly version: 1
  /** Who agents address and sign as. `project.user`, not `project.name`. */
  readonly user?: string
  readonly company?: string
  readonly editor?: Project['editor']
  /** The language agents SPEAK. `outputLanguage` is a separate decision and is
   *  deliberately not held here. */
  readonly language?: string
  /** The engine every agent on this machine runs on unless its project or the
   *  agent itself says otherwise. RESOLVED at run time, never copied into a
   *  project: absent on the agent and chosen here are two states. */
  readonly engine?: EngineId
  readonly model?: Model
}

/** A parse that keeps the file when only the engine or model is unknown: a
 *  name this build does not know is dropped with a warning, because losing
 *  the person's name over a misspelt engine would be the worse outcome. */
export type ParsedDefaults = Parsed<Defaults> & { readonly warnings: readonly Defect[] }

export const NO_DEFAULTS: Defaults = { version: 1 }

/** The keys a new project inherits, in the order the form shows them. */
export const DEFAULT_FIELDS = ['user', 'company', 'editor', 'language'] as const

export function parseDefaults(source: string, path: string): ParsedDefaults {
  const { value, defects } = parseYamlish(source, path)
  const out: Defect[] = [...defects]
  const warnings: Defect[] = []
  const at = (message: string) => out.push({ path, line: 0, message })
  const warn = (message: string) => warnings.push({ path, line: 0, message })

  if (value.version !== 1) at(`version must be 1, got ${JSON.stringify(value.version)}`)

  const text = (node: unknown, field: string): string | undefined => {
    if (node === undefined || node === null) return undefined
    if (typeof node !== 'string') {
      at(`${field} must be a string, got ${JSON.stringify(node)}`)
      return undefined
    }
    return node.trim() === '' ? undefined : node.trim()
  }

  const user = text(value.user, 'user')
  const company = text(value.company, 'company')
  const language = text(value.language, 'language')

  let editor: Defaults['editor']
  if (value.editor !== undefined && value.editor !== null) {
    if (typeof value.editor === 'string' && (EDITORS as readonly string[]).includes(value.editor)) {
      editor = value.editor as Defaults['editor']
    } else {
      at(`editor must be one of ${EDITORS.join(', ')}, got ${JSON.stringify(value.editor)}`)
    }
  }

  const engine = known(value.engine, 'engine', ENGINES, warn) as EngineId | undefined
  const model = known(value.model, 'model', STORED_MODELS, warn) as Model | undefined

  if (out.length > 0) return { ok: false, defects: out, warnings }
  return {
    ok: true,
    warnings,
    value: {
      version: 1,
      ...(user !== undefined ? { user } : {}),
      ...(company !== undefined ? { company } : {}),
      ...(editor !== undefined ? { editor } : {}),
      ...(language !== undefined ? { language } : {}),
      ...(engine !== undefined ? { engine } : {}),
      ...(model !== undefined ? { model } : {}),
    },
  }
}

function known(
  node: unknown,
  field: string,
  offered: readonly string[],
  warn: (message: string) => void,
): string | undefined {
  if (node === undefined || node === null) return undefined
  const name = typeof node === 'string' ? node.trim() : ''
  if (offered.includes(name)) return name
  warn(`${field} must be one of ${offered.join(', ')}, got ${JSON.stringify(node)}; ignored`)
  return undefined
}

export function serializeDefaults(defaults: Defaults): string {
  const lines: string[] = ['version: 1']
  const put = (key: string, v: string | undefined) => {
    if (v !== undefined && v.trim() !== '') lines.push(`${key}: ${scalar(v.trim())}`)
  }
  put('user', defaults.user)
  put('company', defaults.company)
  put('editor', defaults.editor)
  put('language', defaults.language)
  put('engine', defaults.engine)
  put('model', defaults.model)
  return lines.join('\n') + '\n'
}

/**
 * A new project's starting values. THIS COPIES, it does not link: the result is
 * a plain Project the caller writes once, so changing a default later reaches
 * nothing already on disk. A key the project already answers is left exactly as
 * it is, which is why every fill is guarded on `undefined`.
 */
export function withDefaults(project: Project, defaults: Defaults): Project {
  const fill = (own: string | undefined, from: string | undefined): string | undefined =>
    own !== undefined ? own : from
  return {
    ...project,
    user: fill(project.user, defaults.user),
    company: fill(project.company, defaults.company),
    editor: project.editor !== undefined ? project.editor : defaults.editor,
    language: fill(project.language, defaults.language),
  }
}

/**
 * What the machine should hold after a project answered for itself. FILLS ONLY
 * THE BLANKS: a key the machine already holds is never rewritten, so the second
 * project asking a different company does not move what the first one seeded.
 * Nothing here decides to write; the caller does, and only when asked.
 */
export function seedDefaults(held: Defaults, project: Project): Defaults {
  const lifted = defaultsFrom(project)
  const take = <K extends (typeof DEFAULT_FIELDS)[number]>(key: K): Defaults[K] =>
    held[key] !== undefined ? held[key] : lifted[key]
  return {
    version: 1,
    ...(take('user') !== undefined ? { user: take('user') } : {}),
    ...(take('company') !== undefined ? { company: take('company') } : {}),
    ...(take('editor') !== undefined ? { editor: take('editor') } : {}),
    ...(take('language') !== undefined ? { language: take('language') } : {}),
    ...(held.engine !== undefined ? { engine: held.engine } : {}),
    ...(held.model !== undefined ? { model: held.model } : {}),
  }
}

/** Whether seeding would actually add anything, so a form only offers the
 *  choice when there is a blank for it to fill. */
export function seedAdds(held: Defaults, project: Project): boolean {
  return JSON.stringify(seedDefaults(held, project)) !== JSON.stringify(held)
}

/** What this machine would hand a new project, taken from a project already
 *  set up. Offered as a starting point for the form, never applied by itself. */
export function defaultsFrom(project: Project): Defaults {
  return {
    version: 1,
    ...(project.user !== undefined ? { user: project.user } : {}),
    ...(project.company !== undefined ? { company: project.company } : {}),
    ...(project.editor !== undefined ? { editor: project.editor } : {}),
    ...(project.language !== undefined ? { language: project.language } : {}),
  }
}
