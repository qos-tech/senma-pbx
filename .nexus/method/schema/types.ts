/**
 * The on-disk contract. Every screen reads these shapes and every agent writes
 * them, so a change here is a change to the product's storage format.
 *
 * `column` is the board's; `origin` is how the item got here, and it is what
 * lets the quick path and the long path share one board without pretending a
 * quick item passed through stages it skipped.
 */

export const COLUMNS = [
  'backlog',
  'planning',
  'specs',
  'dev',
  'tests',
  'review',
  'done',
] as const

export type Column = (typeof COLUMNS)[number]

/** How the item reached the board. `manual` never had an agent at all. */
export const ORIGINS = ['full', 'quick', 'manual'] as const
export type Origin = (typeof ORIGINS)[number]

/** The roster the fork installs, by the id it installs them under. Most own a
 *  board stage; `evo-master` and `gitops` own none, because orchestrating and
 *  version control happen at every stage rather than at one. */
export const AGENTS = [
  'analyst',
  'architect',
  'dev',
  'gitops',
  'pm',
  'qa',
  'quick-flow-solo-dev',
  'sm',
  'ux-designer',
  'evo-master',
] as const

export type AgentId = (typeof AGENTS)[number]

/** A person is `davidson`; an agent is `agent:dev`. The reader tells them
 *  apart by prefix, and both write to the same field. */
export type Author = string

export const ISSUE_KEY = /^[a-z0-9][a-z0-9-]*$/i

export interface Comment {
  readonly who: Author
  readonly at: string
  readonly text: string
}

export interface Task {
  /** Stable across reordering, never the index. */
  readonly id: string
  readonly text: string
  readonly done: boolean
  /** The criteria this task serves, by `Criterion.id`. A reference to the
   *  spec's own list, so a criterion deleted later leaves an id here that
   *  resolves to nothing, reported by unresolvedBacklinks rather than
   *  refusing to open the file. */
  readonly ac?: readonly string[]
  /** Set only when the task may be skipped without failing a criterion.
   *  Absent is the ordinary case, so no spec gains a line by being read. */
  readonly optional?: boolean
}

export interface BoardItem {
  readonly key: string
  readonly title: string
  readonly column: Column
  readonly origin: Origin
  /** The issue whose work exposed this issue. It is provenance, not hierarchy. */
  readonly foundIn?: string
  /** Issues this one waits on before it may START. DECLARED, never inferred:
   *  the app cannot tell that two issues touch the same files, so this is the
   *  person's statement of order, not collision protection. Held only on the
   *  blocked side, so no reverse list can disagree with it. */
  readonly blockedBy?: readonly string[]
  readonly epic?: string
  /** The feature this issue came from. Absent on quick and manual issues:
   *  the feature layer is a place to go, never a gate to pass. */
  readonly feature?: string
  /** The timebox this issue belongs to, if any. A field, not a column. */
  readonly sprint?: string
  /** Which workflow this issue runs, by slug. A reference to project data, so
   *  a workflow that was deleted leaves a name here that resolves to nothing. */
  readonly workflow?: string
  /** Whether the app may start the next stage once one finishes well. Absent
   *  or false means every step is handed over by a person. */
  readonly auto?: boolean
  /** Off the board, still on disk. Reversible by design: this is the everyday
   *  way to clear a card, and deleting is the one that takes the files. */
  readonly archived?: boolean
  readonly labels: readonly string[]
  /** Spec keys, in the order they should be worked. */
  readonly specs: readonly string[]
  /** Set while an agent holds this item. */
  readonly agent?: AgentId
}

export interface Board {
  readonly version: 1
  readonly columns: readonly Column[]
  readonly items: readonly BoardItem[]
}

/** One acceptance criterion, stable id so the screen can reorder and edit
 *  without losing which line is which. */
export interface Criterion {
  readonly id: string
  readonly text: string
}

/** A mock an agent wrote so a decision could be SEEN before it became code.
 *  `rel` is under `.nexus/assets/`, and the viewer allows it no script, so an
 *  artifact is a drawing the app renders, never a page the app runs. */
export interface IssueArtifact {
  readonly name: string
  readonly rel: string
  /** Which stage drew it, so a mock is read as that stage's output. */
  readonly producedBy?: Column
}

/**
 * The issue: the board card. Its sections are TYPED, not a raw markdown blob:
 * `context` is the description (prose), `criteria` is a list the screen edits
 * item by item. The markdown body of the file is generated from these, so the
 * agent reads normal `## Context` / `## Acceptance Criteria` prose while the
 * screen keeps editing structure. See method/schema/sections.ts.
 */
export interface Issue {
  readonly key: string
  readonly title: string
  readonly column: Column
  readonly origin: Origin
  /** The issue whose work exposed this issue. See BoardItem.foundIn. */
  readonly foundIn?: string
  /** Issues this one waits on before it may start. See BoardItem.blockedBy. */
  readonly blockedBy?: readonly string[]
  readonly epic?: string
  readonly feature?: string
  readonly sprint?: string
  /** Which workflow this issue runs, by slug. See BoardItem.workflow. */
  readonly workflow?: string
  /** Whether the app may start the next stage once one finishes well. */
  readonly auto?: boolean
  /** Off the board, still on disk. See BoardItem.archived. */
  readonly archived?: boolean
  /** The column the stage that just ran decided this issue should go to next,
   *  and why. Planning writes it after the analysis: the route is a judgement
   *  made once the work is understood, not a guess made before it. */
  readonly routeTo?: Column
  readonly routeWhy?: string
  readonly labels: readonly string[]
  readonly specs: readonly string[]
  /** The description, plain prose. Shown and edited as the issue's body. */
  readonly context: string
  readonly criteria: readonly Criterion[]
  readonly comments: readonly Comment[]
  /** The mocks written for this issue, listed so they can be opened. */
  readonly artifacts: readonly IssueArtifact[]
  /** Named targets: a pull request, a design doc, anything worth returning to.
   *  The app never merges, so a PR link here is how the work leaves. */
  readonly links: Readonly<Record<string, string>>
}

/**
 * The spec: one story of the method (Story, Acceptance Criteria, Tasks). Same
 * typed-section rule as the issue, `story` is prose, `criteria` and `tasks`
 * are lists the screen owns; the body mirrors them.
 */
/** How the quick path decided to work: straight through, or plan first and
 *  review after. The router chooses; the screen shows and can change it. */
export const ROUTES = ['one-shot', 'plan-code-review'] as const
export type Route = (typeof ROUTES)[number]

export interface Spec {
  readonly key: string
  readonly title: string
  readonly issue: string
  readonly done: boolean
  /** Set only on a quick spec, where a route was chosen. */
  readonly route?: Route
  /** The story statement, plain prose. */
  readonly story: string
  readonly criteria: readonly Criterion[]
  readonly tasks: readonly Task[]
  readonly links: Readonly<Record<string, string>>
}

/** The five planning docs a feature owns, in the order the method produces
 *  them. The board reads from `epics`. */
export const DOC_KINDS = ['brief', 'prd', 'ux', 'architecture', 'epics'] as const
export type DocKind = (typeof DOC_KINDS)[number]

/** Which agent owns each doc, so the feature page hands the right one over. */
export const DOC_OWNER: Record<DocKind, AgentId> = {
  brief: 'analyst',
  prd: 'pm',
  ux: 'ux-designer',
  architecture: 'architect',
  epics: 'pm',
}

/**
 * Which method skill writes each doc, by the canonicalId the fork installs.
 * Naming the skill is the point: the app knows the method, so handing a slot
 * over never means describing the work and hoping the agent picks the right
 * workflow. `prd` and `architecture` also appear in the board's stage
 * contract, at issue scope rather than feature scope; it is one skill either
 * way.
 */
export const DOC_SKILL: Record<DocKind, string> = {
  brief: 'evo-create-product-brief',
  prd: 'evo-create-prd',
  ux: 'evo-create-ux-design',
  architecture: 'evo-create-architecture',
  epics: 'evo-create-epics-and-stories',
}

/**
 * What each doc wants written before it. The method builds on itself, so
 * handing over a PRD with no brief means asking someone to write from
 * nothing. Absent means it needs none.
 */
export const DOC_NEEDS: Partial<Record<DocKind, DocKind>> = {
  prd: 'brief',
  ux: 'prd',
  architecture: 'prd',
  epics: 'architecture',
}

/** The research documents a feature can also carry. They are not slots: a
 *  feature has them or it does not, and nothing waits on them. */
export const RESEARCH_KINDS = ['market-research', 'domain-research', 'technical-research'] as const
export type ResearchKind = (typeof RESEARCH_KINDS)[number]

/** Any document that lives in a feature's folder, slot or research. */
export type FeatureDoc = DocKind | ResearchKind

/** A doc slot's state, derived from the file: absent, present-and-unfinished,
 *  or marked done. `draft` and `done` both mean the file exists. */
export type DocState = 'empty' | 'draft' | 'done'

/**
 * A feature: the container for one initiative's planning docs. It owns a
 * folder `features/<key>/` with up to five docs, and it originates issues that
 * carry `feature: <key>`. A feature is optional to the board; issues can exist
 * without one.
 */
export interface Feature {
  readonly key: string
  readonly name: string
  readonly status: 'planning' | 'shipped' | 'archived'
  /** Which of the five docs exist on disk, and in what state. */
  readonly docs: Readonly<Record<DocKind, DocState>>
  /** Issue keys this feature has originated, if any. */
  readonly issues: readonly string[]
}

/**
 * A workflow: an ordered run through the board's stages, and a policy for what
 * happens between them. Project data, authored by you, living in
 * `.nexus/workflows.yaml`. The stages already know their skill and where a card
 * goes next, so this adds only how far to go and whether to carry on unasked.
 */
export interface Workflow {
  readonly id: string
  readonly name: string
  readonly summary: string
  /** The path taken, in order. Contiguous along the method's own chain. */
  readonly steps: readonly Column[]
  /** Which stage table the steps are read from. */
  readonly origin: Origin
  /** Where a run stops on its own and waits for you. */
  readonly stops: readonly Column[]
}

/**
 * A sprint: a timebox holding a set of issues. Orthogonal to the column and the
 * feature. App-written, one file per sprint under `sprints/<key>.yaml`.
 */
export interface Sprint {
  readonly key: string
  readonly name: string
  readonly starts?: string
  readonly ends?: string
  /** Issue keys in this sprint. Membership, not order. */
  readonly issues: readonly string[]
  /** Absent is stopped. The default mode stops each issue at Review. */
  readonly loop?: 'to-review' | 'full-cycle'
  /** Simultaneous issues owned by this loop, from one through four. */
  readonly loopLimit?: number
  /** Consecutive failed turns. Two stops the loop. */
  readonly loopFailures?: number
  /** Issues that already received the one allowed conflict-resolution run. */
  readonly loopReconciled?: readonly string[]
  /** App-written facts and decisions, newest last. */
  readonly loopLedger?: readonly string[]
}

/**
 * One story inside an epic, in the method's shape: a role/capability/benefit
 * statement and acceptance criteria. This is the row the bridge turns into a
 * board issue, so `title` and `criteria` map straight onto the issue.
 */
export interface Story {
  readonly id: string
  readonly title: string
  /** The `As a X, I want Y, so that Z` statement, one prose block. */
  readonly statement: string
  /** Acceptance criteria, each a Given/When/Then line or a plain sentence. */
  readonly criteria: readonly string[]
  /** Earlier stories this one needs, each written `<epic id>/<story id>` or as
   *  a bare story id. The doc names stories because an issue key does not exist
   *  until the card is minted; the bridge resolves these to keys. */
  readonly dependsOn?: readonly string[]
}

/** One epic: a goal and the stories that deliver it. */
export interface Epic {
  readonly id: string
  readonly title: string
  readonly goal: string
  readonly stories: readonly Story[]
}

/**
 * The epics doc, fully typed because the app computes issues from it. Its
 * sections are the method's: a requirements inventory (kept as prose, it is
 * reference not structure), and the epic and story breakdown, which is
 * structure the screen edits and the bridge reads. The markdown body mirrors
 * the frontmatter, so an agent reads a normal epic breakdown.
 */
export interface Epics {
  /** Requirements inventory and coverage, prose the screen shows but does not
   *  decompose: FR, NFR, additional requirements, the coverage map. */
  readonly requirements: string
  readonly epics: readonly Epic[]
}

/**
 * The project's own settings, `.nexus/project.yaml`. The identity and language
 * fields are the method's (it names them project_name, user_name,
 * communication_language, document_output_language, user_skill_level) and are
 * what every workflow reads to know who it works for and in which language to
 * speak and to write.
 */
/** The aliases Claude Code accepts. */
export const MODELS = ['haiku', 'sonnet', 'opus', 'fable'] as const

/** The visible catalog reported by codex-cli 0.147.0 on 2026-08-13. */
export const CODEX_MODELS = [
  'gpt-5.6-sol',
  'gpt-5.6-terra',
  'gpt-5.6-luna',
  'gpt-5.5',
  'gpt-5.4',
  'gpt-5.4-mini',
  'gpt-5.3-codex-spark',
] as const

/** Preserved on read so an obsolete choice is never deleted silently. */
export const LEGACY_CODEX_MODELS = ['gpt-5.1-codex', 'gpt-5.1-codex-mini'] as const

export const STORED_MODELS = [...MODELS, ...CODEX_MODELS, ...LEGACY_CODEX_MODELS] as const
export type Model = (typeof STORED_MODELS)[number]

/**
 * How talkative an agent is. `quiet` works and reports at the end, `normal`
 * says what it is doing, `collaborative` surfaces options and asks before it
 * commits. This becomes a line of the prompt, not a flag.
 */
export const VOICES = ['quiet', 'normal', 'collaborative'] as const
export type Voice = (typeof VOICES)[number]

/** One agent's settings. Both fields are optional: an agent with neither runs
 *  on the session default, which is what every agent did before this existed. */
export interface AgentConfig {
  readonly model?: Model
  readonly voice?: Voice
  readonly engine?: EngineId
  /** The KIND of work this agent does, when no model was named. It survives an
   *  engine change, which a model name cannot, and it never wins over a model
   *  the person chose by hand. */
  readonly tier?: Tier
}

/** What may reach the operating system. Two states out of six ever do, and each
 *  gets its own switch; `mute` silences the banner and changes nothing on
 *  screen, because the indicators are the app working, not the app nagging. */
export interface NotifyConfig {
  readonly enabled?: boolean
  readonly questions?: boolean
  readonly failures?: boolean
  readonly mute?: boolean
}

export const NOTIFY_FIELDS = ['enabled', 'questions', 'failures', 'mute'] as const

/** The code engines an agent can run on. Both are a CLI the person installed
 *  and logged into themselves; the app never holds a credential for either. */
export const ENGINES = ['claude-code', 'codex'] as const
export type EngineId = (typeof ENGINES)[number]

/** What each engine calls the models it offers. Sending an agent's `opus` to
 *  Codex asks OpenAI for an Anthropic model, so the argv builder checks this
 *  and not only the screen: project.yaml is a file a person edits by hand. */
export const ENGINE_MODELS: Record<EngineId, readonly string[]> = {
  'claude-code': MODELS,
  codex: CODEX_MODELS,
}

export function engineOffersModel(engine: EngineId, model: string): boolean {
  return ENGINE_MODELS[engine].includes(model)
}

/**
 * What KIND of work an agent is being given, said without naming a model.
 * `mechanical` is work whose answer is already decided and only has to be
 * carried out; `judgement` is work where the answer is what is being produced.
 * A default written as a model name breaks the moment the engine changes, so
 * the intent is what is stored and each engine resolves it for itself.
 */
export const TIERS = ['mechanical', 'judgement'] as const
export type Tier = (typeof TIERS)[number]

/**
 * The one place a model name may stand as a default. An engine with no honest
 * equivalent for a tier leaves it undefined rather than naming a near miss:
 * the screen says there is none, and the run falls back to the engine's own
 * session default, which is what happened before any of this existed.
 */
export const TIER_MODELS: Record<EngineId, Partial<Record<Tier, string>>> = {
  'claude-code': { mechanical: 'sonnet', judgement: 'opus' },
  codex: { mechanical: 'gpt-5.4', judgement: 'gpt-5.6-sol' },
}

/** The model this engine offers for this intent, or none. Never a near miss:
 *  a caller that gets undefined has to say so rather than pick something. */
export function tierModel(engine: EngineId, tier: Tier): string | undefined {
  return TIER_MODELS[engine][tier]
}

/**
 * The three ways work leaves a lane, chosen per project. `manual` is the one
 * that needs nothing of the machine, which is why it is the fallback rather
 * than an offer that cannot be taken.
 */
export const EXITS = ['pr', 'merge', 'manual'] as const
export type Exit = (typeof EXITS)[number]

/**
 * What a fresh checkout needs before an agent is put in it. A worktree carries
 * only what git tracks, so the `.env` and the `node_modules` the person has
 * been working with are not there and nothing an agent runs would work.
 */
export interface Setup {
  /** Files to copy in from the main checkout, as patterns. Absent means the
   *  default, which is `.env*`; an empty list means copy nothing. */
  readonly copy?: readonly string[]
  /** One command run in the new checkout before the agent spawns. It travels
   *  with the repository, so the app shows it and asks before ever running it. */
  readonly command?: string
}

export interface Project {
  readonly name: string
  /** The company or client the work belongs to, if any. */
  readonly company?: string
  /** Who the agents are working with, used to sign and to address. */
  readonly user?: string
  /** The language agents SPEAK to the person in. */
  readonly language?: string
  /** The language agents WRITE files in, which is often not the spoken one. */
  readonly outputLanguage?: string
  readonly skill?: 'beginner' | 'intermediate' | 'expert'
  /** How much a run may do unattended: `edits` lets it write inside the
   *  project, `manual` refuses every tool, `bypass` refuses nothing. */
  readonly permissions?: 'edits' | 'manual' | 'bypass'
  /** Which editor a deep link opens: the scheme, not a path. */
  readonly editor?: 'vscode' | 'cursor' | 'windsurf' | 'zed'
  /** The branch lanes are cut from and diffed against. Recorded rather than
   *  taken from HEAD, so a lane is never cut from another lane. */
  readonly mainLine?: string
  /** How a finished lane leaves the app: open a pull request, merge it into
   *  the main line here, or say the branch name and stop. Absent means the
   *  app picks by what this machine can actually do. */
  readonly exit?: Exit
  /** What a lane's own checkout needs before an agent works in it. Absent means
   *  copy `.env*` and run nothing, which is what most projects want. */
  readonly setup?: Setup
  readonly feature?: string
  /** The sprint the board defaults to showing, if any. */
  readonly sprint?: string
  /** When the app may interrupt you, and whether it may at all. Absent means
   *  every switch on, since a notification nobody asked to silence is the
   *  behaviour the plan chose. */
  readonly notify?: NotifyConfig
  /** Per-agent model and voice, by agent id. Absent means the default. */
  readonly agents?: Readonly<Partial<Record<AgentId, AgentConfig>>>
  /** The engine every stage and agent falls back to. Absent is not the same as
   *  `claude-code`: it means nothing was said, which is what lets the rung
   *  below it be reported rather than guessed at. */
  readonly engine?: EngineId
  /** The engine a kind of work runs on, by column. Lives here rather than on
   *  `Stage` because a stage is compiled into the app and this is the
   *  project's choice. */
  readonly stageEngines?: Readonly<Partial<Record<Column, EngineId>>>
}

/**
 * A branch name this app will hand to git. `-` leads an option, `..` and `@{`
 * resolve as revisions, and the rest is what `git check-ref-format` refuses.
 * The Rust side keeps the same rule in `safe_ref`; the two must agree.
 */
export const SAFE_REF = /^(?!-)(?!\/)(?!.*\.\.)(?!.*@\{)(?!.*\/\/)[^\s~^:?*[\\\x00-\x20\x7f]+(?<![./])$/

export function isSafeRef(ref: string): boolean {
  return ref !== '' && !ref.endsWith('.lock') && SAFE_REF.test(ref)
}

/** Where a defect is, so the screen can point at the line instead of saying
 *  the file is bad. */
export interface Defect {
  readonly path: string
  readonly line: number
  readonly message: string
}

/** A refusal on its own, which any `Parsed<T>` can be assigned from: the
 *  defects of a failed split do not depend on what was being parsed. */
export interface Refused {
  readonly ok: false
  readonly defects: readonly Defect[]
}

/** `salvaged` is what a REFUSED read could still make out, and it is set only
 *  when the caller asked for it. A refusal stays a refusal: every writer tests
 *  `ok`, so a partial value can never be serialized back over the file. */
export type Parsed<T> =
  | { readonly ok: true; readonly value: T }
  | (Refused & { readonly salvaged?: T })
