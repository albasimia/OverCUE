import Sortable from 'sortablejs'
import { nextTick, onBeforeUnmount, onMounted, ref, watch, type Ref } from 'vue'

interface SortableOrderOptions {
  element: Ref<HTMLElement | null>
  currentIDs: () => string[]
  persist: (ids: string[]) => Promise<void>
}

export function useSortableOrder(options: SortableOrderOptions) {
  const isSaving = ref(false)
  const errorMessage = ref<string | null>(null)
  let sortable: Sortable | null = null

  function restoreDOMOrder() {
    sortable?.sort(options.currentIDs(), false)
  }

  async function persistDOMOrder() {
    if (!sortable || isSaving.value) return

    const nextIDs = sortable.toArray()
    const currentIDs = options.currentIDs()
    if (nextIDs.length !== currentIDs.length || new Set(nextIDs).size !== nextIDs.length) {
      restoreDOMOrder()
      return
    }
    if (nextIDs.every((id, index) => id === currentIDs[index])) return

    isSaving.value = true
    errorMessage.value = null
    sortable.option('disabled', true)
    try {
      await options.persist(nextIDs)
    } catch (error) {
      errorMessage.value = error instanceof Error ? error.message : String(error)
      await nextTick()
      restoreDOMOrder()
    } finally {
      isSaving.value = false
      sortable.option('disabled', false)
    }
  }

  function attach(element: HTMLElement | null) {
    sortable?.destroy()
    sortable = null
    if (!element) return

    sortable = Sortable.create(element, {
      animation: 140,
      handle: '.drag-handle',
      draggable: '[data-sortable-id]',
      dataIdAttr: 'data-sortable-id',
      ghostClass: 'drag-ghost',
      chosenClass: 'drag-chosen',
      onEnd: () => {
        void persistDOMOrder()
      },
    })
  }

  onMounted(() => attach(options.element.value))

  watch(
    options.element,
    (element) => attach(element),
    { flush: 'post' },
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

  return { isSaving, errorMessage }
}
