import Sortable from 'sortablejs'
import { nextTick, onBeforeUnmount, ref, watch, type Ref } from 'vue'

interface SortableOrderOptions {
  element: Ref<HTMLElement | null>
  currentIDs: () => string[]
  persist?: (ids: string[]) => Promise<void>
  onChange?: (ids: string[]) => void
}

export function useSortableOrder(options: SortableOrderOptions) {
  const isSaving = ref(false)
  const errorMessage = ref<string | null>(null)
  let sortable: Sortable | null = null

  function restoreDOMOrder() {
    sortable?.sort(options.currentIDs(), false)
  }

  async function handleDOMOrder() {
    if (!sortable || isSaving.value) return

    const activeSortable = sortable
    const nextIDs = activeSortable.toArray()
    const currentIDs = options.currentIDs()
    if (nextIDs.length !== currentIDs.length || new Set(nextIDs).size !== nextIDs.length) {
      restoreDOMOrder()
      return
    }
    if (nextIDs.every((id, index) => id === currentIDs[index])) return

    errorMessage.value = null
    if (options.onChange) {
      options.onChange(nextIDs)
      await nextTick()
      if (sortable === activeSortable) restoreDOMOrder()
      return
    }

    if (!options.persist) {
      restoreDOMOrder()
      return
    }

    isSaving.value = true
    activeSortable.option('disabled', true)
    try {
      await options.persist(nextIDs)
    } catch (error) {
      errorMessage.value = error instanceof Error ? error.message : String(error)
      await nextTick()
      if (sortable === activeSortable) restoreDOMOrder()
    } finally {
      isSaving.value = false
      if (sortable === activeSortable) activeSortable.option('disabled', false)
    }
  }

  function attach(element: HTMLElement | null) {
    sortable?.destroy()
    sortable = null
    if (!element) return

    sortable = Sortable.create(element, {
      animation: 140,
      handle: '.drag-handle',
      draggable: '.native-list-row[data-sortable-id]',
      dataIdAttr: 'data-sortable-id',
      ghostClass: 'drag-ghost',
      chosenClass: 'drag-chosen',
      onEnd: () => {
        void handleDOMOrder()
      },
    })
    restoreDOMOrder()
  }

  watch(
    options.element,
    async (element) => {
      await nextTick()
      if (options.element.value !== element) return
      attach(element)
    },
    { immediate: true, flush: 'post' },
  )

  watch(
    () => options.currentIDs().join('\u0000'),
    async () => {
      if (isSaving.value) return
      await nextTick()
      restoreDOMOrder()
    },
  )

  onBeforeUnmount(() => {
    sortable?.destroy()
    sortable = null
  })

  return { isSaving, errorMessage, restoreDOMOrder }
}
