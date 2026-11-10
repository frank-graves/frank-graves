/**
 * Refreshes the auto-updated sections of the profile README from the GitHub API.
 * Runs in CI (daily) or locally: bun run scripts/ship-log.ts
 */
import { readFile, writeFile } from 'node:fs/promises'

const USER = 'frank-graves'
const README = new URL('../README.md', import.meta.url)
const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN

const headers: Record<string, string> = {
  accept: 'application/vnd.github+json',
  'user-agent': `${USER}-profile-readme`,
  ...(token ? { authorization: `Bearer ${token}` } : {}),
}

type Repo = {
  name: string
  html_url: string
  description: string | null
  fork: boolean
  archived: boolean
  pushed_at: string
}

type CommitItem = {
  commit: { message: string; author: { date: string } }
}

async function gh<T>(path: string): Promise<T | null> {
  const res = await fetch(`https://api.github.com${path}`, { headers })
  if (res.status === 404 || res.status === 409) return null // missing or empty repo
  if (!res.ok) throw new Error(`github api ${res.status} on ${path}`)
  return (await res.json()) as T
}

function swap(src: string, start: string, end: string, body: string): string {
  const open = `<!-- ${start} -->`
  const close = `<!-- ${end} -->`
  const a = src.indexOf(open)
  const b = src.indexOf(close)
  if (a === -1 || b === -1 || b < a) throw new Error(`markers missing: ${start} / ${end}`)
  return src.slice(0, a + open.length) + `\n${body}\n` + src.slice(b)
}

const repos = (await gh<Repo[]>(`/users/${USER}/repos?per_page=100&sort=pushed`)) ?? []
const recent = repos
  .filter((r) => !r.fork && !r.archived && r.name !== USER)
  .slice(0, 5)

const projects = recent.map(
  (r) => `- [**${r.name}**](${r.html_url})${r.description ? ` — ${r.description}` : ''}`,
)

const commits = await Promise.all(
  recent.slice(0, 4).map(async (r) => {
    const list = await gh<CommitItem[]>(`/repos/${USER}/${r.name}/commits?per_page=1`)
    const c = list?.[0]?.commit
    if (!c) return null
    const msg = c.message.split('\n')[0].replaceAll('`', "'").slice(0, 72)
    return `- \`${r.name}\` ← ${msg} <sub>${c.author.date.slice(0, 10)}</sub>`
  }),
)
const activity = commits.filter((line): line is string => line !== null)

const readme = await readFile(README, 'utf8')
let next = swap(
  readme,
  'AUTO-UPDATE:START',
  'AUTO-UPDATE:END',
  projects.length ? projects.join('\n') : '*Nothing shipped lately. The AI is on vacation.*',
)
next = swap(
  next,
  'ACTIVITY-START',
  'ACTIVITY-END',
  activity.length ? activity.join('\n') : '*Terminal is quiet. Suspiciously quiet.*',
)

if (next === readme) {
  console.log('ship log: no change')
} else {
  await writeFile(README, next)
  console.log(`ship log: ${projects.length} projects, ${activity.length} commits`)
}
