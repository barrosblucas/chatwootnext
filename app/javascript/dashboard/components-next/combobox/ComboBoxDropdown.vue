<script setup>
import { ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  open: {
    type: Boolean,
    required: true,
  },
  options: {
    type: Array,
    required: true,
  },
  searchPlaceholder: {
    type: String,
    default: '',
  },
  emptyState: {
    type: String,
    default: '',
  },
  multiple: {
    type: Boolean,
    default: false,
  },
  selectedValues: {
    type: [String, Number, Array],
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'search', 'close']);

const { t } = useI18n();

const searchValue = defineModel('searchValue', {
  type: String,
  default: '',
});

const searchInput = ref(null);
const listRef = ref(null);
const highlightedIndex = ref(0);

const isSelected = option => {
  if (Array.isArray(props.selectedValues)) {
    return props.selectedValues.includes(option.value);
  }
  return option.value === props.selectedValues;
};

const scrollToHighlighted = () => {
  nextTick(() => {
    if (!listRef.value) return;
    const items = listRef.value.querySelectorAll('li[role="option"]');
    const targetItem = items[highlightedIndex.value];
    targetItem?.scrollIntoView?.({ block: 'nearest' });
  });
};

watch(
  () => props.options,
  () => {
    highlightedIndex.value = 0;
  }
);

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      highlightedIndex.value = 0;
    }
  }
);

const onInputSearch = event => {
  searchValue.value = event.target.value;
  emit('search', event.target.value);
};

const onInputKeydown = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    emit('close');
    return;
  }

  if (event.key === 'ArrowDown') {
    event.preventDefault();
    if (props.options.length > 0) {
      highlightedIndex.value =
        (highlightedIndex.value + 1) % props.options.length;
      scrollToHighlighted();
    }
    return;
  }

  if (event.key === 'ArrowUp') {
    event.preventDefault();
    if (props.options.length > 0) {
      highlightedIndex.value =
        highlightedIndex.value <= 0
          ? props.options.length - 1
          : highlightedIndex.value - 1;
      scrollToHighlighted();
    }
    return;
  }

  if (event.key === 'Enter') {
    event.preventDefault();
    if (
      highlightedIndex.value >= 0 &&
      highlightedIndex.value < props.options.length
    ) {
      emit('select', props.options[highlightedIndex.value]);
    } else if (props.options.length === 1) {
      emit('select', props.options[0]);
    }
  }
};

const focus = () => {
  if (searchInput.value) {
    searchInput.value.focus();
    const len = searchInput.value.value?.length || 0;
    searchInput.value.setSelectionRange?.(len, len);
  }
};

defineExpose({
  focus,
});
</script>

<template>
  <div
    v-show="open"
    class="absolute z-50 w-full mt-1 transition-opacity duration-200 border rounded-md shadow-lg bg-n-solid-1 border-n-strong"
  >
    <div class="relative border-b border-n-strong">
      <Spinner
        v-if="loading"
        :size="16"
        class="absolute top-2.5 start-3 text-n-slate-11"
      />
      <Icon
        v-else
        icon="i-lucide-search"
        class="absolute top-2.5 size-4 start-3"
      />
      <input
        ref="searchInput"
        :value="searchValue"
        type="search"
        :placeholder="searchPlaceholder || t('COMBOBOX.SEARCH_PLACEHOLDER')"
        class="reset-base w-full py-2 !ps-10 !pe-2 text-sm focus:outline-none border-none rounded-t-md bg-n-solid-1 text-n-slate-12"
        @input="onInputSearch"
        @keydown="onInputKeydown"
      />
    </div>
    <ul
      ref="listRef"
      class="py-1 mb-0 overflow-auto max-h-60"
      role="listbox"
      :aria-multiselectable="multiple"
    >
      <li
        v-for="(option, index) in options"
        :key="`${option.value}-${index}`"
        class="flex items-center justify-between w-full gap-2 px-3 py-2 text-sm transition-colors duration-150 cursor-pointer hover:bg-n-alpha-2"
        :class="{
          'bg-n-alpha-2': isSelected(option) || highlightedIndex === index,
        }"
        role="option"
        :aria-selected="isSelected(option)"
        @click.stop="emit('select', option)"
        @mouseenter="highlightedIndex = index"
      >
        <span
          :class="{
            'font-medium': isSelected(option),
          }"
          class="text-n-slate-12"
        >
          {{ option.label }}
        </span>
        <span
          v-if="isSelected(option)"
          class="flex-shrink-0 i-lucide-check size-4 text-n-slate-11"
        />
      </li>
      <li v-if="options.length === 0" class="px-3 py-2 text-sm text-n-slate-11">
        {{ emptyState || t('COMBOBOX.EMPTY_STATE') }}
      </li>
    </ul>
  </div>
</template>
