/**
 * Reads `.nexus/board.yaml` into a Board or a list of defects that carry line
 * numbers. Every rule the format promises is checked here, once: nothing
 * downstream re-validates, and nothing upstream half-validates.
 */

import { COLUMNS, ORIGINS, AGENTS, ISSUE_KEY } from './types'
import type { Board, BoardItem, Column, Defect, Origin, Parsed } from './types'
import { parseYamlish } from './yamlish'
import type { Node } from './yamlish'

/* A COLUMN THAT WAS REMOVED, and where its cards go instead. Removing one from
   COLUMNS made every board that still named it refuse to load, taking the
   whole project with it. A retired column is migrated in silence: the person
   asked for it to be gone, not for their work to stop. */
export const RETIRED: Record<string, Column> = { architecture: 'planning' }

export function parseBoard(source: string, path: string): Parsed<Board> {
  const { value, defects } = parseYamlish(source, path)
  const out: Defect[] = [...defects]
  const at = (message: string) => out.push({ path, line: 0, message })

  if (value.version !== 1) at(`version must be 1, got ${JSON.stringify(value.version)}`)

  const columns = readColumns(value.columns, path, out)
  const items = readItems(value.items, path, out)

  /* Cross-item rules live here, where both sides are in hand. */
  const seen = new Set<string>()
  for (const item of items) {
    if (seen.has(item.key)) at(`duplicate item key "${item.key}"`)
    seen.add(item.key)
    if (!columns.includes(item.column)) {
      at(`item "${item.key}" sits in column "${item.column}", which this board does not declare`)
    }
    /* `epic` NAMES A GROUP IN THE FEATURE'S epics.md, never another card. This
       rule read it as an item key, so the app's own bridge wrote seventeen
       issues from a feature's stories and then refused the board it had just
       written, with every issue on it and no way back. A group with no card
       behind it is the normal case, not a defect. */
  }

  if (out.length > 0) return { ok: false, defects: out }
  return { ok: true, value: { version: 1, columns, items } }
}

function readColumns(node: Node | undefined, path: string, out: Defect[]): Column[] {
  if (!Array.isArray(node)) {
    out.push({ path, line: 0, message: 'columns must be a list' })
    return [...COLUMNS]
  }
  const columns: Column[] = []
  for (const entry of node) {
    if (typeof entry === 'string' && entry in RETIRED) continue
    if (typeof entry !== 'string' || !(COLUMNS as readonly string[]).includes(entry)) {
      out.push({ path, line: 0, message: `unknown column ${JSON.stringify(entry)}` })
      continue
    }
    columns.push(entry as Column)
  }
  return columns
}

function readItems(node: Node | undefined, path: string, out: Defect[]): BoardItem[] {
  if (node === undefined || node === null) return []
  if (!Array.isArray(node)) {
    out.push({ path, line: 0, message: 'items must be a list' })
    return []
  }

  const items: BoardItem[] = []
  node.forEach((entry, i) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      out.push({ path, line: 0, message: `items[${i}] must be a map` })
      return
    }
    const item = readItem(entry, i, path, out)
    if (item) items.push(item)
  })
  return items
}

function readItem(
  entry: { [key: string]: Node },
  i: number,
  path: string,
  out: Defect[],
): BoardItem | null {
  const at = (message: string) => out.push({ path, line: 0, message: `items[${i}]: ${message}` })
  let bad = false

  const key = entry.key
  if (typeof key !== 'string' || !ISSUE_KEY.test(key)) {
    at(`key must match ${ISSUE_KEY}, got ${JSON.stringify(key)}`)
    bad = true
  }
  const title = entry.title
  if (typeof title !== 'string' || title.trim() === '') {
    at('title must be a non-empty string')
    bad = true
  }
  /* A card left in a retired column MOVES rather than refusing: the column is
     gone, the work is not. */
  const named = typeof entry.column === 'string' ? entry.column : entry.column
  const column = typeof named === 'string' && named in RETIRED ? RETIRED[named] : named
  if (typeof column !== 'string' || !(COLUMNS as readonly string[]).includes(column)) {
    at(`column must be one of ${COLUMNS.join(', ')}, got ${JSON.stringify(column)}`)
    bad = true
  }
  const origin = entry.origin
  if (typeof origin !== 'string' || !(ORIGINS as readonly string[]).includes(origin)) {
    at(`origin must be one of ${ORIGINS.join(', ')}, got ${JSON.stringify(origin)}`)
    bad = true
  }

  const foundIn = optionalString(entry.foundIn, 'foundIn', at)
  if (foundIn !== undefined && !ISSUE_KEY.test(foundIn)) at(`foundIn must match ${ISSUE_KEY}, got ${JSON.stringify(foundIn)}`)
  /* Only the SHAPE is judged here. A key that names nothing, an archived
     blocker, or a cycle parses clean and is reported on screen: refusing the
     board would take every card down over one hand-edit. */
  const blockedBy = optionalKeyList(entry.blockedBy, 'blockedBy', at)
  const epic = optionalString(entry.epic, 'epic', at)
  const feature = optionalString(entry.feature, 'feature', at)
  const sprint = optionalString(entry.sprint, 'sprint', at)
  const labels = stringList(entry.labels, 'labels', at)
  const specs = stringList(entry.specs, 'specs', at)

  /* A workflow is a reference to project data, not a member of a fixed set:
     an item naming one that was deleted parses clean and resolves to none. */
  const workflow = optionalString(entry.workflow, 'workflow', at)

  let auto: BoardItem['auto']
  if (entry.auto !== undefined && entry.auto !== null) {
    if (typeof entry.auto === 'boolean') auto = entry.auto
    else at(`auto must be true or false, got ${JSON.stringify(entry.auto)}`)
  }

  let archived: BoardItem['archived']
  if (entry.archived !== undefined && entry.archived !== null) {
    if (typeof entry.archived === 'boolean') archived = entry.archived
    else at(`archived must be true or false, got ${JSON.stringify(entry.archived)}`)
  }

  let agent: BoardItem['agent']
  if (entry.agent !== undefined && entry.agent !== null) {
    if (typeof entry.agent === 'string' && (AGENTS as readonly string[]).includes(entry.agent)) {
      agent = entry.agent as BoardItem['agent']
    } else {
      at(`agent must be one of ${AGENTS.join(', ')}, got ${JSON.stringify(entry.agent)}`)
    }
  }

  if (bad) return null
  return {
    key: key as string,
    title: (title as string).trim(),
    column: column as Column,
    origin: origin as Origin,
    foundIn,
    blockedBy,
    epic,
    feature,
    sprint,
    workflow,
    auto,
    archived,
    labels,
    specs,
    agent,
  }
}

function optionalString(
  node: Node | undefined,
  name: string,
  at: (m: string) => void,
): string | undefined {
  if (node === undefined || node === null) return undefined
  if (typeof node !== 'string') {
    at(`${name} must be a string, got ${JSON.stringify(node)}`)
    return undefined
  }
  return node
}

/** A list of issue keys, absent when empty so a file that never named one is
 *  written back without gaining a line it did not have. */
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

/**
 * The one write rule the format promises: a column never moves backwards
 * except by a person's hand. `byHand` is the drag; everything else refuses.
 */
export function mayMove(from: Column, to: Column, byHand: boolean): boolean {
  if (byHand) return true
  return COLUMNS.indexOf(to) >= COLUMNS.indexOf(from)
}
