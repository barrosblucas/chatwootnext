<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBoxDropdown from 'dashboard/components-next/combobox/ComboBoxDropdown.vue';

const props = defineProps({
  options: {
    type: Array,
    required: true,
    validator: value =>
      value.every(option => 'value' in option && 'label' in option),
  },
  placeholder: { type: String, default: '' },
  // Fallback label shown when the selected value is not in `options` yet
  // (e.g. API-backed lists that load lazily on open).
  displayLabel: { type: String, default: '' },
  modelValue: { type: [String, Number], default: '' },
  disabled: { type: Boolean, default: false },
  searchPlaceholder: { type: String, default: '' },
  emptyState: { type: String, default: '' },
  message: { type: String, default: '' },
  hasError: { type: Boolean, default: false },
  useApiResults: { type: Boolean, default: false }, // useApiResults prop to determine if search is handled by API
});

const emit = defineEmits(['update:modelValue', 'search', 'open', 'close']);

const { t } = useI18n();

const selectedValue = ref(props.modelValue);
const open = ref(false);
const search = ref('');
const dropdownRef = ref(null);
const comboboxRef = ref(null);
const triggerButtonRef = ref(null);

const filteredOptions = computed(() => {
  // For API search, don't filter options locally
  if (props.useApiResults && search.value) {
    return props.options;
  }

  // For local search, filter options based on search term
  const searchTerm = search.value.toLowerCase();
  return props.options.filter(option =>
    option.label.toLowerCase().includes(searchTerm)
  );
});
const selectPlaceholder = computed(() => {
  return props.placeholder || t('COMBOBOX.PLACEHOLDER');
});
const selectedLabel = computed(() => {
  const selected = props.options.find(
    option => option.value === selectedValue.value
  );
  return selected?.label ?? (props.displayLabel || selectPlaceholder.value);
});

const focusTrigger = () => {
  const el = triggerButtonRef.value?.$el || triggerButtonRef.value;
  el?.focus?.();
};

const openDropdown = (initialSearch = '') => {
  if (props.disabled) return;
  open.value = true;
  search.value = initialSearch;
  emit('open');
  if (initialSearch) {
    emit('search', initialSearch);
  }
  nextTick(() => dropdownRef.value?.focus());
};

const closeDropdown = (shouldFocusTrigger = false) => {
  if (!open.value) return;
  open.value = false;
  search.value = '';
  emit('close');
  if (shouldFocusTrigger) {
    nextTick(() => focusTrigger());
  }
};

const selectOption = option => {
  if (selectedValue.value === option.value) {
    selectedValue.value = '';
    emit('update:modelValue', '');
  } else {
    selectedValue.value = option.value;
    emit('update:modelValue', option.value);
  }
  closeDropdown(true);
};

const toggleDropdown = () => {
  if (props.disabled) return;
  if (open.value) {
    closeDropdown();
  } else {
    openDropdown();
  }
};

const onTriggerKeydown = event => {
  if (props.disabled) return;

  if (['ArrowDown', 'ArrowUp'].includes(event.key)) {
    event.preventDefault();
    if (!open.value) {
      openDropdown();
    }
    return;
  }

  if (['Enter', ' '].includes(event.key)) {
    event.preventDefault();
    toggleDropdown();
    return;
  }

  if (event.key === 'Escape') {
    if (open.value) {
      event.preventDefault();
      event.stopPropagation();
      closeDropdown(true);
    }
    return;
  }

  const isPrintable =
    event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey;

  if (isPrintable) {
    event.preventDefault();
    openDropdown(event.key);
  }
};

watch(
  () => props.modelValue,
  newValue => {
    selectedValue.value = newValue;
  }
);

defineExpose({
  focus: focusTrigger,
  open: openDropdown,
  close: closeDropdown,
  toggleDropdown,
});
</script>

<template>
  <div
    ref="comboboxRef"
    class="relative w-full min-w-0"
    :class="{
      'cursor-not-allowed': disabled,
      'group/combobox': !disabled,
    }"
    @click.prevent
  >
    <OnClickOutside @trigger="closeDropdown(false)">
      <Button
        ref="triggerButtonRef"
        variant="outline"
        :color="hasError && !open ? 'ruby' : open ? 'blue' : 'slate'"
        :label="selectedLabel"
        trailing-icon
        :disabled="disabled"
        no-animation
        class="justify-between w-full !px-3 !py-2.5 text-n-slate-12 font-normal group-hover/combobox:border-n-slate-6 focus:outline-n-brand"
        :class="{
          focused: open,
          '[&:not(.focused)]:dark:outline-n-weak [&:not(.focused)]:hover:enabled:outline-n-slate-6 [&:not(.focused)]:dark:hover:enabled:outline-n-slate-6':
            !hasError,
        }"
        :icon="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        @click="toggleDropdown"
        @keydown="onTriggerKeydown"
      />

      <ComboBoxDropdown
        ref="dropdownRef"
        v-model:search-value="search"
        :open="open"
        :options="filteredOptions"
        :search-placeholder="searchPlaceholder"
        :empty-state="emptyState"
        :selected-values="selectedValue"
        @search="emit('search', $event)"
        @select="selectOption"
        @close="closeDropdown(true)"
      />

      <p
        v-if="message"
        class="mt-2 mb-0 text-xs truncate transition-all duration-500 ease-in-out"
        :class="{
          'text-n-ruby-9': hasError,
          'text-n-slate-11': !hasError,
        }"
      >
        {{ message }}
      </p>
    </OnClickOutside>
  </div>
</template>
