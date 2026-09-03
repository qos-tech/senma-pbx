/**
 * Reading a project that still runs the OLD method, so it can be archived and
 * started fresh. Pure functions only: the battery imports this file directly,
 * and every path here is a name, never a read. The work under `_evo-output/`
 * is COUNTED and never converted, moved or opened.
 */

/** The old method's work product. Counted for the report, never touched. */
export const WORK_DIR = '_evo-output'

/** The old method's installed tree, beside the work product. */
export const METHOD_DIR = '_evo'

/** Where the skills of both methods land, and the only surface they collide on. */
export const SKILLS_DIR = '.claude/skills'

/**
 * What installing writes into `.claude/skills/`. Listed, not read: the
 * collision must be shown BEFORE the install, while these files are still in
 * the app bundle. The gate holds it against the method tree, so drift fails.
 */
export const INCOMING_SKILLS = [
  'evo-advanced-elicitation',
  'evo-analyst',
  'evo-architect',
  'evo-brainstorming',
  'evo-branch-cleanup',
  'evo-check-implementation-readiness',
  'evo-code-review',
  'evo-commit-message',
  'evo-correct-course',
  'evo-create-architecture',
  'evo-create-epics-and-stories',
  'evo-create-prd',
  'evo-create-product-brief',
  'evo-create-story',
  'evo-create-ux-design',
  'evo-design-mock',
  'evo-dev',
  'evo-dev-story',
  'evo-document-project',
  'evo-domain-research',
  'evo-edit-prd',
  'evo-editorial-review-prose',
  'evo-editorial-review-structure',
  'evo-explain-conflict',
  'evo-generate-project-context',
  'evo-gitops',
  'evo-help',
  'evo-index-docs',
  'evo-lane-ready',
  'evo-market-research',
  'evo-master',
  'evo-party-mode',
  'evo-pm',
  'evo-qa',
  'evo-qa-generate-e2e-tests',
  'evo-quick-dev',
  'evo-quick-flow-solo-dev',
  'evo-quick-spec',
  'evo-read-history',
  'evo-retrospective',
  'evo-shard-doc',
  'evo-sm',
  'evo-sprint-planning',
  'evo-sprint-status',
  'evo-tech-writer',
  'evo-technical-research',
  'evo-ux-designer',
  'evo-validate-prd',
] as const

/** One `_evo-output` tree found in the project, with what it holds. */
export interface WorkTree {
  /** Relative to the project root, so the root tree is exactly `_evo-output`. */
  readonly path: string
  readonly features: number
  readonly stories: number
}

/**
 * What a skill folder means once both sides are known. `collides` is the one
 * that costs something: the same name and often the same description, over a
 * body that loads the old layout, so replacing it leaves nothing to see.
 */
export interface SkillVerdict {
  readonly name: string
  readonly fate: 'collides' | 'old-only'
}

export interface Survey {
  readonly trees: readonly WorkTree[]
  readonly hasOldMethod: boolean
  readonly skills: readonly SkillVerdict[]
}

/** A dated folder, one per day, so a second run on the same day lands in the
 *  same archive and a run tomorrow does not bury today's. */
export function archiveDirName(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `.evo-archive-${y}-${m}-${d}`
}

/** A story file of the old method: `1-1-some-title.md`. Counted only. */
export function isStoryFile(name: string): boolean {
  return /^\d+-\d+-.+\.md$/.test(name)
}

/**
 * Which skills the new install would replace, and which it would leave behind.
 * Sorted by name so the dry run reads the same on every machine, and computed
 * from the two real listings rather than from a remembered number.
 */
/**
 * A skill's body says which method it belongs to. The new one loads out of
 * `.nexus/`, and the two install under the SAME names, so judging by name
 * alone reported a fresh install as the old method and left setup blocked on
 * a project that had already moved across.
 */
export function isNewMethodSkill(body: string): boolean {
  return body.includes('.nexus/method/')
}

export function judgeSkills(installed: readonly string[], incoming: readonly string[]): SkillVerdict[] {
  const arriving = new Set(incoming)
  return [...installed]
    .sort()
    .map((name) => ({ name, fate: arriving.has(name) ? ('collides' as const) : ('old-only' as const) }))
}

export function countFate(skills: readonly SkillVerdict[], fate: SkillVerdict['fate']): number {
  return skills.filter((s) => s.fate === fate).length
}

/**
 * True while the old method still has files where the new one would write.
 * `_evo-output` deliberately never moves, so its presence is NOT part of this:
 * counting it would leave the warning up forever on a project that has fully
 * moved across.
 */
export function hasOldMethodInstalled(survey: Survey): boolean {
  return survey.hasOldMethod || survey.skills.length > 0
}

/** One folder the archive step would move, and whether it still has to. */
export interface ArchiveStep {
  readonly from: string
  readonly to: string
  readonly done: boolean
}

/**
 * The moves the archive would make, in order. Anything already sitting in the
 * archive is marked done rather than moved again, which is what makes a second
 * run safe: nothing is ever written over, so nothing is ever lost.
 */
export function planArchive(
  archive: string,
  skills: readonly SkillVerdict[],
  hasOldMethod: boolean,
  archived: readonly string[],
): ArchiveStep[] {
  const already = new Set(archived)
  const steps: ArchiveStep[] = skills.map((s) => ({
    from: `${SKILLS_DIR}/${s.name}`,
    to: `${archive}/skills/${s.name}`,
    done: already.has(s.name),
  }))
  if (hasOldMethod) {
    steps.push({ from: METHOD_DIR, to: `${archive}/${METHOD_DIR}`, done: already.has(METHOD_DIR) })
  }
  return steps
}

/** What the archive holds and how to undo it, written beside the moved files
 *  so the folder explains itself without this app. */
export function originText(archive: string, steps: readonly ArchiveStep[], trees: readonly WorkTree[]): string {
  const lines: string[] = [
    '# What this folder is',
    '',
    `Nexus Studio moved the OLD method's installed files here on ${archive.replace('.evo-archive-', '')},`,
    'so the new method could be installed without writing over them.',
    '',
    '## What was moved',
    '',
  ]
  for (const step of steps) lines.push(`- \`${step.from}\` is now \`${step.to}\``)
  lines.push('', '## What was NOT touched', '')
  if (trees.length === 0) {
    lines.push('- No `_evo-output` tree was found in this project.')
  } else {
    for (const tree of trees) {
      lines.push(`- \`${tree.path}\`: ${tree.features} features, ${tree.stories} story files, left exactly as it was.`)
    }
  }
  lines.push(
    '',
    'The old work product stays where it is. Nothing here was deleted.',
    '',
    '## How to put it back',
    '',
    'Move each folder above from its new path back to its old one, then delete this folder by hand.',
    '',
  )
  return lines.join('\n')
}
