/**
 * A reader for the YAML subset this format writes: maps, lists of scalars,
 * lists of maps, quoted and bare scalars, two-space indentation. Not YAML -
 * anchors, multi-line scalars and flow maps are refused, on purpose.
 *
 * Why not a YAML library: the repository has no YAML dependency, and a defect
 * here must carry a line number so the screen can point at it. Both come free
 * when the reader is ours; neither comes free from a library.
 */

import type { Defect } from './types'

export type Scalar = string | number | boolean | null
export type Node = Scalar | Node[] | { [key: string]: Node }

export interface YamlResult {
  readonly value: { [key: string]: Node }
  readonly defects: readonly Defect[]
}

interface Line {
  readonly n: number
  readonly indent: number
  readonly text: string
}

const FLOW_LIST = /^\[(.*)\]$/

/** A flow map is refused rather than read. `{ text: 'x', done: false }` looks
 *  like a map and is not one here, and reading its first colon as a key made
 *  `{ text` a field name, so a written task silently became no task at all.
 *  `{}` is the exception: it carries no pair to lose, and it is how a file
 *  says it has none. */
const FLOW_MAP = /^\{(.*)\}$/

function flowMapPairs(text: string): string | null {
  const m = FLOW_MAP.exec(text)
  if (m === null) return null
  const inner = (m[1] ?? '').trim()
  return inner === '' ? null : inner
}

/** `key: |` and `key: >`, with the chomping indicators YAML allows after them.
 *  The method's own agent files carry these, so the shape is not exotic. */
const BLOCK_OPEN = /^([^:]+):\s*([|>])[-+]?\d*\s*$/

/** The lines belonging to a block scalar: everything indented deeper than the
 *  key, blank lines included, until a line comes back to the key's level. */
function readBlock(raws: readonly string[], from: number, indent: number): [string, number] {
  const body: string[] = []
  let i = from
  while (i < raws.length) {
    const raw = raws[i] ?? ''
    if (raw.trim() !== '') {
      const at = raw.length - raw.trimStart().length
      if (at <= indent) break
    }
    body.push(raw)
    i++
  }
  while (body.length > 0 && (body[body.length - 1] ?? '').trim() === '') body.pop()
  const strip = body.reduce(
    (least, line) => (line.trim() === '' ? least : Math.min(least, line.length - line.trimStart().length)),
    Number.MAX_SAFE_INTEGER,
  )
  const text = body.map((line) => (line.trim() === '' ? '' : line.slice(strip))).join('\n')
  return [text, i]
}

/** `>` folds each paragraph onto one line; `|` keeps the newlines. Emitted as
 *  a double-quoted scalar, which `unquote` already decodes. */
function quote(text: string, folded: boolean): string {
  const body = folded
    ? text
        .split('\n\n')
        .map((para) => para.split('\n').join(' ').trim())
        .join('\n\n')
    : text
  return `"${body.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"`
}

export function parseYamlish(source: string, path: string): YamlResult {
  const defects: Defect[] = []
  const lines: Line[] = []

  /* A BLOCK SCALAR IS TAKEN WHOLE, before anything else looks at the text.
     `requirements: |` opens prose that is indented under its key, and reading
     those lines as structure is what refused a whole epics file and left the
     board empty with no error on screen. `#` inside prose is prose. */
  const raws = source.split('\n')
  for (let i = 0; i < raws.length; i++) {
    const raw = raws[i] ?? ''
    const noComment = stripComment(raw)
    if (noComment.trim() === '') continue
    const indent = noComment.length - noComment.trimStart().length
    if (indent % 2 !== 0) {
      defects.push({ path, line: i + 1, message: `indentation of ${indent} is not a multiple of 2` })
      continue
    }
    const text = noComment.trim()
    const block = BLOCK_OPEN.exec(text)
    if (block !== null) {
      const [body, through] = readBlock(raws, i + 1, indent)
      lines.push({ n: i + 1, indent, text: `${block[1]}: ${quote(body, block[2] === '>')}` })
      i = through - 1
      continue
    }
    lines.push({ n: i + 1, indent, text })
  }

  const [value, read] = readMap(lines, 0, 0, path, defects)

  /* READING LESS THAN THE WHOLE FILE IS A DEFECT, NEVER A QUIETER ANSWER.
     `readMap` stops at a list item sitting at its own key's level, which real
     YAML allows and this subset does not. Discarding that index returned a
     document missing everything below, with nothing on screen to say so. */
  if (read < lines.length) {
    const line = lines[read]!
    defects.push({ path, line: line.n, message: unreadMessage(line.text) })
  }

  return { value, defects }
}

/** Why the reader stopped, and the edit that moves it on. A list written at
 *  its key's own level is legal YAML and the commonest way to arrive here. */
function unreadMessage(text: string): string {
  if (text.startsWith('- ') || text === '-') {
    return 'a list item at its key\'s own indentation is not read here; indent the list two spaces under its key'
  }
  return `nothing below this line was read: "${text}"`
}

/** A `#` opens a comment only at line start or after whitespace, as in YAML -
 *  `docs/prd.md#section` is a value, not a comment. */
function stripComment(raw: string): string {
  let inSingle = false
  let inDouble = false
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i]
    if (c === '\\' && inDouble) i++
    else if (c === "'" && !inDouble) inSingle = !inSingle
    else if (c === '"' && !inSingle) inDouble = !inDouble
    else if (c === '#' && !inSingle && !inDouble) {
      if (i === 0 || raw[i - 1] === ' ' || raw[i - 1] === '\t') return raw.slice(0, i)
    }
  }
  return raw
}

function readMap(
  lines: Line[],
  start: number,
  indent: number,
  path: string,
  defects: Defect[],
): [{ [key: string]: Node }, number] {
  const out: { [key: string]: Node } = {}
  let i = start

  while (i < lines.length) {
    const line = lines[i]!
    if (line.indent < indent) break
    if (line.indent > indent) {
      defects.push({ path, line: line.n, message: `unexpected indent of ${line.indent}, expected ${indent}` })
      i++
      continue
    }
    if (line.text.startsWith('- ') || line.text === '-') break

    const colon = findColon(line.text)
    if (colon === -1) {
      defects.push({ path, line: line.n, message: `expected "key: value", got "${line.text}"` })
      i++
      continue
    }

    const key = unquote(line.text.slice(0, colon).trim())
    const rest = line.text.slice(colon + 1).trim()

    if (key in out) {
      defects.push({ path, line: line.n, message: `duplicate key "${key}"` })
    }

    if (rest !== '') {
      if (FLOW_MAP.test(rest)) {
        if (flowMapPairs(rest) !== null) {
          defects.push({ path, line: line.n, message: `${key} is a flow map; write its keys on their own lines` })
        } else {
          out[key] = {}
        }
        i++
        continue
      }
      const flow = FLOW_LIST.exec(rest)
      out[key] = flow
        ? (flow[1] ?? '').trim() === ''
          ? []
          : (flow[1] ?? '').split(',').map((s) => scalar(s.trim()))
        : scalar(rest)
      i++
      continue
    }

    const next = lines[i + 1]
    if (!next || next.indent <= indent) {
      out[key] = null
      i++
      continue
    }
    if (next.text.startsWith('- ') || next.text === '-') {
      const [list, after] = readList(lines, i + 1, next.indent, path, defects)
      out[key] = list
      i = after
    } else {
      const [map, after] = readMap(lines, i + 1, next.indent, path, defects)
      out[key] = map
      i = after
    }
  }

  return [out, i]
}

function readList(
  lines: Line[],
  start: number,
  indent: number,
  path: string,
  defects: Defect[],
): [Node[], number] {
  const out: Node[] = []
  let i = start

  while (i < lines.length) {
    const line = lines[i]!
    if (line.indent !== indent || (!line.text.startsWith('- ') && line.text !== '-')) break

    const rest = line.text === '-' ? '' : line.text.slice(2).trim()

    if (rest === '') {
      defects.push({ path, line: line.n, message: 'empty list item' })
      i++
      continue
    }

    if (FLOW_MAP.test(rest)) {
      defects.push({ path, line: line.n, message: 'a flow map is not read here; write "- key: value" on its own lines' })
      i++
      continue
    }


    const colon = findColon(rest)
    if (colon === -1) {
      out.push(scalar(rest))
      i++
      continue
    }

    /* `- key: value` opens an inline map; its remaining keys sit two deeper. */
    const key = unquote(rest.slice(0, colon).trim())
    const value = rest.slice(colon + 1).trim()
    const item: { [key: string]: Node } = {}
    if (value !== '') {
      const flow = FLOW_LIST.exec(value)
      item[key] = flow
        ? (flow[1] ?? '').trim() === ''
          ? []
          : (flow[1] ?? '').split(',').map((s) => scalar(s.trim()))
        : scalar(value)
      i++
    } else {
      const next = lines[i + 1]
      if (next && next.indent > indent + 2) {
        const [nested, after] = next.text.startsWith('- ')
          ? readList(lines, i + 1, next.indent, path, defects)
          : readMap(lines, i + 1, next.indent, path, defects)
        item[key] = nested
        i = after
      } else {
        item[key] = null
        i++
      }
    }

    while (i < lines.length && lines[i]!.indent === indent + 2 && !lines[i]!.text.startsWith('- ')) {
      const [more, after] = readMap(lines, i, indent + 2, path, defects)
      Object.assign(item, more)
      i = after
    }

    out.push(item)
  }

  return [out, i]
}

/** The first `:` that ends a key, followed by space or end, outside quotes. */
function findColon(text: string): number {
  let inSingle = false
  let inDouble = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '\\' && inDouble) i++
    else if (c === "'" && !inDouble) inSingle = !inSingle
    else if (c === '"' && !inSingle) inDouble = !inDouble
    else if (c === ':' && !inSingle && !inDouble) {
      if (i + 1 === text.length || text[i + 1] === ' ') return i
    }
  }
  return -1
}

function scalar(text: string): Scalar {
  if (text === 'null' || text === '~') return null
  if (text === 'true') return true
  if (text === 'false') return false
  const quoted = unquote(text)
  if (quoted !== text) return quoted
  if (/^-?\d+$/.test(text)) return Number(text)
  if (/^-?\d+\.\d+$/.test(text)) return Number(text)
  return text
}

/** Double quotes decode the three escapes the serializer emits; single
 *  quotes stay literal, as in YAML. */
function unquote(text: string): string {
  if (text.length < 2) return text
  const first = text[0]
  const last = text[text.length - 1]
  if (first === "'" && last === "'") return text.slice(1, -1)
  if (first !== '"' || last !== '"') return text
  const inner = text.slice(1, -1)
  let out = ''
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i]
    if (c === '\\' && i + 1 < inner.length) {
      const next = inner[i + 1]
      out += next === 'n' ? '\n' : next
      i++
    } else out += c
  }
  return out
}
