import type { OverCUESnapshot, ReorderRequest } from './types'

const API_BASE = import.meta.env.VITE_OVERCUE_API_BASE ?? '/api/v1'

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

export const overcueAPI = {
  snapshot: () => request<OverCUESnapshot>('/snapshot'),
  reorderPresets: (ids: string[]) => request<OverCUESnapshot>('/presets/order', {
    method: 'PUT',
    body: JSON.stringify({ ids } satisfies ReorderRequest),
  }),
  reorderGroupPresets: (ids: string[]) => request<OverCUESnapshot>('/group-presets/order', {
    method: 'PUT',
    body: JSON.stringify({ ids } satisfies ReorderRequest),
  }),
}
