/**
 * The generic shape of a planning doc that is not the epics file. The method
 * builds brief, PRD, UX and architecture by appending `##` sections as it
 * works, and which sections exist varies by project type, so these are read as
 * an ordered list of headed blocks rather than frozen into one interface per
 * doc. The screen edits a section at a time; the file keeps its frontmatter.
 */

export interface Section {
  /** The `##` heading, without its hashes. */
  readonly heading: string
  /** Everything under the heading until the next one, verbatim. */
  readonly body: string
}

export interface Doc {
  /** The frontmatter block, kept byte for byte so the method's own bookkeeping
   *  (stepsCompleted, inputDocuments) survives an edit made here. */
  readonly frontmatter: string
  /** Anything before the first `##`, usually the `#` title line. */
  readonly preamble: string
  readonly sections: readonly Section[]
}

const FENCE = '---'

/** Splits a doc into its frontmatter, preamble and `##` sections. A file with
 *  no frontmatter and no headings is all preamble, which still round-trips. */
export function parseDoc(source: string): Doc {
  const lines = source.split('\n')
  let frontmatter = ''
  let rest = lines

  if (lines[0]?.trim() === FENCE) {
    const end = lines.findIndex((l, i) => i > 0 && l.trim() === FENCE)
    if (end > 0) {
      frontmatter = lines.slice(1, end).join('\n')
      rest = lines.slice(end + 1)
    }
  }

  const preamble: string[] = []
  const sections: Section[] = []
  let heading: string | null = null
  let body: string[] = []

  const flush = () => {
    if (heading !== null) sections.push({ heading, body: body.join('\n').trim() })
    body = []
  }

  for (const line of rest) {
    const match = /^##\s+(.*)$/.exec(line)
    if (match !== null) {
      flush()
      heading = match[1]!.trim()
      continue
    }
    if (heading === null) preamble.push(line)
    else body.push(line)
  }
  flush()

  return { frontmatter, preamble: preamble.join('\n').trim(), sections }
}

/** Writes a doc back. Round-trips whatever parseDoc read, so editing one
 *  section never disturbs the others or the frontmatter above them. */
export function serializeDoc(doc: Doc): string {
  const parts: string[] = []
  if (doc.frontmatter.trim() !== '') parts.push(FENCE, doc.frontmatter, FENCE, '')
  if (doc.preamble.trim() !== '') parts.push(doc.preamble.trim(), '')
  for (const section of doc.sections) {
    parts.push(`## ${section.heading}`, '')
    if (section.body.trim() !== '') parts.push(section.body.trim(), '')
  }
  return parts.join('\n').trimEnd() + '\n'
}

/** Replaces one section's body, leaving every other byte of the doc alone. */
export function setSection(doc: Doc, heading: string, body: string): Doc {
  const sections = doc.sections.map((s) => (s.heading === heading ? { ...s, body } : s))
  return { ...doc, sections }
}

export function addSection(doc: Doc, heading: string): Doc {
  if (doc.sections.some((s) => s.heading === heading)) return doc
  return { ...doc, sections: [...doc.sections, { heading, body: '' }] }
}
