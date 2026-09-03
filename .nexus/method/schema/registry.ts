/**
 * The app's home registry, `~/.nexus/projects.yaml`. Roots, the name and face
 * you gave each one, and the groups they sit in: a menu, not project state, so
 * losing this file loses a menu and never any work.
 */

import type { Defect, Parsed } from './types'
import { parseYamlish } from './yamlish'
import { scalar } from './serialize'

/** Icon names, not icons: this layer has no React and no lucide-react. The
 *  picker in src/lib/projectFace.ts maps each one to a component. */
export const PROJECT_ICONS = [
  'box', 'code', 'compass', 'database', 'flask', 'globe', 'hammer', 'layers',
  'leaf', 'rocket', 'shield', 'sparkles', 'terminal', 'zap',
] as const

export type ProjectIcon = (typeof PROJECT_ICONS)[number]

/** Only hues the token palette already defines. There is no free colour. */
export const PROJECT_COLOURS = ['neutral', 'evo', 'iris', 'amber', 'coral'] as const

export type PaletteColour = (typeof PROJECT_COLOURS)[number]

/** A colour is a palette name, or a custom `#rrggbb` the person picked. */
export type ProjectColour = PaletteColour | string

export const HEX_COLOUR = /^#[0-9a-f]{6}$/i

export function isPaletteColour(value: string): value is PaletteColour {
  return (PROJECT_COLOURS as readonly string[]).includes(value)
}

const SLUG = /^[A-Za-z0-9][A-Za-z0-9-]*$/

export interface ProjectGroup {
  readonly id: string
  readonly name: string
}

/** A file name under `~/.nexus/icons/`, never a path: the app copies the
 *  chosen image there, so a moved or deleted original never blanks a card. */
export const ICON_IMAGE = /^[A-Za-z0-9][A-Za-z0-9._-]*\.(png|jpg|jpeg|webp|svg)$/

export interface RegistryEntry {
  readonly root: string
  readonly opened: string
  readonly name?: string
  /** A drawn icon. Mutually exclusive with `iconImage`. */
  readonly icon?: ProjectIcon
  /** An image the person picked. Mutually exclusive with `icon`. */
  readonly iconImage?: string
  readonly colour?: ProjectColour
  readonly group?: string
  /** Kept at the top of its section. Written only when true, so a project
   *  that was never pinned carries no key at all. */
  readonly pinned?: boolean
}

export interface Registry {
  readonly version: 1
  readonly groups: readonly ProjectGroup[]
  readonly projects: readonly RegistryEntry[]
}

export const EMPTY_REGISTRY: Registry = { version: 1, groups: [], projects: [] }

/** An absolute path on any OS Studio runs on: POSIX `/…`, a Windows drive
 *  `C:\…` or `C:/…`, or a UNC share `\\server\…`. A relative path is refused,
 *  so the registry never lists a root it could not reopen. The dialog on
 *  Windows hands back `C:\…`, which is absolute yet starts with no slash, so a
 *  slash-only check drops every project the moment the file is reread. */
export function isAbsoluteRoot(root: string): boolean {
  return root.startsWith('/') || /^[A-Za-z]:[\\/]/.test(root) || root.startsWith('\\\\')
}

/** The last path segment, split on either separator, so a Windows root shows
 *  its folder and not the whole `C:\…` line. Trailing separators are ignored. */
export function basename(root: string): string {
  const parts = root.split(/[\\/]+/).filter((s) => s !== '')
  return parts[parts.length - 1] ?? root
}

export function parseRegistry(source: string, path: string): Parsed<Registry> {
  const { value, defects } = parseYamlish(source, path)
  const out: Defect[] = [...defects]
  const at = (message: string) => out.push({ path, line: 0, message })

  if (value.version !== 1) at(`version must be 1, got ${JSON.stringify(value.version)}`)

  const groups = readGroups(value.groups, at)
  const projects = readProjects(value.projects, groups, at)

  if (out.length > 0) return { ok: false, defects: out }
  return { ok: true, value: { version: 1, groups, projects } }
}

/** Groups are read first, so a project may be checked against them. */
function readGroups(node: unknown, at: (message: string) => void): ProjectGroup[] {
  const groups: ProjectGroup[] = []
  if (node === undefined || node === null) return groups
  if (!Array.isArray(node)) {
    at('groups must be a list')
    return groups
  }
  node.forEach((entry, i) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      at(`groups[${i}] must be a map`)
      return
    }
    const id = (entry as Record<string, unknown>).id
    const name = (entry as Record<string, unknown>).name
    if (typeof id !== 'string' || !SLUG.test(id)) {
      at(`groups[${i}].id must be a slug, got ${JSON.stringify(id)}`)
      return
    }
    if (typeof name !== 'string' || name.trim() === '') {
      at(`groups[${i}].name must be a name, got ${JSON.stringify(name)}`)
      return
    }
    if (groups.some((g) => g.id === id)) {
      at(`groups[${i}] repeats id ${id}`)
      return
    }
    groups.push({ id, name })
  })
  return groups
}

function readProjects(
  node: unknown,
  groups: readonly ProjectGroup[],
  at: (message: string) => void,
): RegistryEntry[] {
  const projects: RegistryEntry[] = []
  if (node === undefined || node === null) return projects
  if (!Array.isArray(node)) {
    at('projects must be a list')
    return projects
  }
  node.forEach((raw, i) => {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      at(`projects[${i}] must be a map`)
      return
    }
    const entry = raw as Record<string, unknown>
    const root = entry.root
    const opened = entry.opened
    if (typeof root !== 'string' || !isAbsoluteRoot(root)) {
      at(`projects[${i}].root must be an absolute path, got ${JSON.stringify(root)}`)
      return
    }
    if (typeof opened !== 'string' || Number.isNaN(Date.parse(opened))) {
      at(`projects[${i}].opened is not a date: ${JSON.stringify(opened)}`)
      return
    }
    if (projects.some((p) => p.root === root)) {
      at(`projects[${i}] repeats root ${root}`)
      return
    }

    const name = entry.name
    if (name !== undefined && (typeof name !== 'string' || name.trim() === '')) {
      at(`projects[${i}].name must be a name, got ${JSON.stringify(name)}`)
      return
    }
    const icon = entry.icon
    if (icon !== undefined && !PROJECT_ICONS.includes(icon as ProjectIcon)) {
      at(`projects[${i}].icon is not one of the offered icons: ${JSON.stringify(icon)}`)
      return
    }
    const iconImage = entry.iconImage
    if (iconImage !== undefined && (typeof iconImage !== 'string' || !ICON_IMAGE.test(iconImage))) {
      at(`projects[${i}].iconImage is not an image file name: ${JSON.stringify(iconImage)}`)
      return
    }
    if (icon !== undefined && iconImage !== undefined) {
      at(`projects[${i}] carries both an icon and an image, so neither wins`)
      return
    }
    const colour = entry.colour
    if (
      colour !== undefined &&
      (typeof colour !== 'string' || (!isPaletteColour(colour) && !HEX_COLOUR.test(colour)))
    ) {
      at(`projects[${i}].colour is neither a palette name nor a #rrggbb: ${JSON.stringify(colour)}`)
      return
    }
    const group = entry.group
    if (group !== undefined && (typeof group !== 'string' || !groups.some((g) => g.id === group))) {
      at(`projects[${i}].group names no group: ${JSON.stringify(group)}`)
      return
    }
    /* Only `true` is a pin. A written `false` is the default spelled out,
       which the writer never emits, so reading one means a hand edit. */
    const pinned = entry.pinned
    if (pinned !== undefined && pinned !== true) {
      at(`projects[${i}].pinned must be true or absent, got ${JSON.stringify(pinned)}`)
      return
    }

    projects.push({
      root,
      opened,
      ...(name !== undefined ? { name: name as string } : {}),
      ...(icon !== undefined ? { icon: icon as ProjectIcon } : {}),
      ...(iconImage !== undefined ? { iconImage: iconImage as string } : {}),
      ...(colour !== undefined ? { colour: colour as ProjectColour } : {}),
      ...(group !== undefined ? { group: group as string } : {}),
      ...(pinned === true ? { pinned: true } : {}),
    })
  })
  return projects
}

export function serializeRegistry(registry: Registry): string {
  const lines: string[] = ['version: 1']
  if (registry.groups.length > 0) {
    lines.push('groups:')
    for (const g of registry.groups) {
      lines.push(`  - id: ${g.id}`)
      lines.push(`    name: ${scalar(g.name)}`)
    }
  }
  if (registry.projects.length > 0) {
    lines.push('projects:')
    for (const p of registry.projects) {
      lines.push(`  - root: ${scalar(p.root)}`)
      lines.push(`    opened: ${p.opened}`)
      if (p.name !== undefined) lines.push(`    name: ${scalar(p.name)}`)
      if (p.icon !== undefined) lines.push(`    icon: ${p.icon}`)
      if (p.iconImage !== undefined) lines.push(`    iconImage: ${scalar(p.iconImage)}`)
      /* Quoted, because a custom colour starts with a hash and a bare hash
         opens a comment: written raw, "#3fb27f" would read back as nothing. */
      if (p.colour !== undefined) lines.push(`    colour: ${scalar(p.colour)}`)
      if (p.group !== undefined) lines.push(`    group: ${p.group}`)
      if (p.pinned === true) lines.push('    pinned: true')
    }
  }
  return lines.join('\n') + '\n'
}

/** Registers or refreshes a root, most recent first. An entry already known
 *  keeps the name, face and group it was given; only `opened` moves. */
export function touch(registry: Registry, root: string, now: string): Registry {
  const known = registry.projects.find((p) => p.root === root)
  const rest = registry.projects.filter((p) => p.root !== root)
  const entry: RegistryEntry = known !== undefined ? { ...known, opened: now } : { root, opened: now }
  return { version: 1, groups: registry.groups, projects: [entry, ...rest] }
}

/** Forgets a root. The registry is a menu, so this touches no folder. */
export function forget(registry: Registry, root: string): Registry {
  return { ...registry, projects: registry.projects.filter((p) => p.root !== root) }
}

/** Removes a group and releases its projects, which become ungrouped. */
export function removeGroup(registry: Registry, id: string): Registry {
  return {
    version: 1,
    groups: registry.groups.filter((g) => g.id !== id),
    projects: registry.projects.map((p) => (p.group === id ? strip(p) : p)),
  }
}

function strip(entry: RegistryEntry): RegistryEntry {
  const { group: _group, ...rest } = entry
  return rest
}

/** Applies an edit, dropping a field the form cleared so it is never written
 *  as an empty value. */
export function describe(registry: Registry, root: string, patch: Partial<RegistryEntry>): Registry {
  return {
    ...registry,
    projects: registry.projects.map((p) => (p.root === root ? prune({ ...p, ...patch }) : p)),
  }
}

function prune(entry: RegistryEntry): RegistryEntry {
  const out: Record<string, unknown> = { root: entry.root, opened: entry.opened }
  if (entry.name !== undefined && entry.name.trim() !== '') out.name = entry.name.trim()
  if (entry.icon !== undefined && entry.iconImage === undefined) out.icon = entry.icon
  if (entry.iconImage !== undefined) out.iconImage = entry.iconImage
  if (entry.colour !== undefined) out.colour = entry.colour
  if (entry.group !== undefined) out.group = entry.group
  if (entry.pinned === true) out.pinned = true
  return out as unknown as RegistryEntry
}

/** Pins or unpins a root. Unpinning drops the key rather than writing false,
 *  so the file only ever states the pins that exist. */
export function pin(registry: Registry, root: string, pinned: boolean): Registry {
  return describe(registry, root, { pinned: pinned ? true : undefined })
}

/** Pinned first, and inside each half the order the caller already had, which
 *  is most recently opened first. Sorting the view leaves `touch` alone. */
export function byPin(projects: readonly RegistryEntry[]): RegistryEntry[] {
  return [...projects].sort((a, b) => Number(b.pinned === true) - Number(a.pinned === true))
}

/** A slug from a free-text group name, kept unique against the ones taken. */
export function groupId(name: string, taken: readonly string[]): string {
  const base =
    name
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^A-Za-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .toLowerCase() || 'group'
  let id = base
  let n = 2
  while (taken.includes(id)) id = `${base}-${n++}`
  return id
}
