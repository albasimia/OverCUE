import type { OverCUESnapshot, ReorderRequest } from './types'

const API_BASE = import.meta.env.VITE_OVERCUE_API_BASE ?? '/api/v1'
let sessionTokenPromise: Promise<string> | null = null

export class OverCUEAPIError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message)
    this.name = 'OverCUEAPIError'
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    cache: 'no-store',
    headers: {
      Accept: 'application/json',
      ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
      ...init?.headers,
    },
  })

  if (!response.ok) {
    const message = await response.text().catch(() => '')
    throw new OverCUEAPIError(message || response.statusText, response.status)
  }

  return response.json() as Promise<T>
}

async function sessionToken(): Promise<string> {
  sessionTokenPromise ??= request<{ token: string }>('/session').then(({ token }) => token)
  return sessionTokenPromise
}

async function writeRequest<T>(path: string, body: unknown): Promise<T> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const token = await sessionToken()
    try {
      return await request<T>(path, {
        method: 'PUT',
        headers: { 'X-OverCUE-Session': token },
        body: JSON.stringify(body),
      })
    } catch (error) {
      if (!(error instanceof OverCUEAPIError) || error.status !== 403 || attempt > 0) {
        throw error
      }
      sessionTokenPromise = null
    }
  }
  throw new Error('OverCUE session could not be refreshed.')
}

export const overcueAPI = {
  snapshot: () => request<OverCUESnapshot>('/snapshot'),
  reorderPresets: (ids: string[]) => writeRequest<OverCUESnapshot>(
    '/presets/order',
    { ids } satisfies ReorderRequest,
  ),
  reorderGroupPresets: (ids: string[]) => writeRequest<OverCUESnapshot>(
    '/group-presets/order',
    { ids } satisfies ReorderRequest,
  ),
}
