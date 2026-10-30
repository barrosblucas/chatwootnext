import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import ComboBox from '../ComboBox.vue';

const OPTIONS = [
  { value: 'support', label: 'Customer Support' },
  { value: 'sales', label: 'Sales Department' },
  { value: 'billing', label: 'Billing & Finance' },
];

describe('ComboBox.vue', () => {
  let wrapper;

  const mountComboBox = (props = {}, options = {}) => {
    return mount(ComboBox, {
      props: {
        options: OPTIONS,
        ...props,
      },
      global: {
        stubs: {
          OnClickOutside: {
            template: '<div><slot /></div>',
          },
          Icon: true,
          Spinner: true,
        },
      },
      ...options,
    });
  };

  beforeEach(() => {
    wrapper?.unmount();
  });

  describe('Rendering', () => {
    it('renders placeholder when no option is selected', () => {
      wrapper = mountComboBox({ placeholder: 'Select destination' });
      expect(wrapper.find('button').text()).toContain('Select destination');
    });

    it('renders selected option label when modelValue matches an option', () => {
      wrapper = mountComboBox({ modelValue: 'sales' });
      expect(wrapper.find('button').text()).toContain('Sales Department');
    });

    it('renders displayLabel fallback when selected value is not in options', () => {
      wrapper = mountComboBox({
        modelValue: 'unknown',
        displayLabel: 'Archived Department',
      });
      expect(wrapper.find('button').text()).toContain('Archived Department');
    });
  });

  describe('Mouse Interactions', () => {
    it('opens and closes dropdown on trigger click', async () => {
      wrapper = mountComboBox();
      const trigger = wrapper.find('button');
      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });

      expect(dropdown.props('open')).toBe(false);

      await trigger.trigger('click');
      expect(dropdown.props('open')).toBe(true);
      expect(wrapper.emitted('open')).toBeTruthy();

      await trigger.trigger('click');
      expect(dropdown.props('open')).toBe(false);
      expect(wrapper.emitted('close')).toBeTruthy();
    });

    it('selects option when clicking an item in dropdown', async () => {
      wrapper = mountComboBox();
      await wrapper.find('button').trigger('click');

      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });
      const optionItems = dropdown.findAll('li[role="option"]');
      expect(optionItems).toHaveLength(3);

      await optionItems[1].trigger('click');

      expect(wrapper.emitted('update:modelValue')?.[0]).toEqual(['sales']);
      expect(dropdown.props('open')).toBe(false);
    });

    it('deselects value when clicking an already selected item', async () => {
      wrapper = mountComboBox({ modelValue: 'support' });
      await wrapper.find('button').trigger('click');

      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });
      const optionItems = dropdown.findAll('li[role="option"]');

      await optionItems[0].trigger('click');

      expect(wrapper.emitted('update:modelValue')?.[0]).toEqual(['']);
    });
  });

  describe('Keyboard Interactions on Trigger', () => {
    it('opens dropdown and starts search when user types a printable character', async () => {
      wrapper = mountComboBox();
      const trigger = wrapper.find('button');
      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });

      await trigger.trigger('keydown', { key: 'b' });
      await nextTick();

      expect(dropdown.props('open')).toBe(true);
      expect(wrapper.emitted('open')).toBeTruthy();
      expect(wrapper.emitted('search')?.[0]).toEqual(['b']);

      // Options should be filtered by 'b' -> "Billing & Finance"
      expect(dropdown.props('options')).toEqual([
        { value: 'billing', label: 'Billing & Finance' },
      ]);
    });

    it('opens dropdown on ArrowDown or ArrowUp key', async () => {
      wrapper = mountComboBox();
      const trigger = wrapper.find('button');
      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });

      await trigger.trigger('keydown', { key: 'ArrowDown' });
      expect(dropdown.props('open')).toBe(true);

      wrapper.unmount();
      wrapper = mountComboBox();
      const trigger2 = wrapper.find('button');
      const dropdown2 = wrapper.findComponent({ name: 'ComboBoxDropdown' });

      await trigger2.trigger('keydown', { key: 'ArrowUp' });
      expect(dropdown2.props('open')).toBe(true);
    });

    it('toggles dropdown on Enter or Space key', async () => {
      wrapper = mountComboBox();
      const trigger = wrapper.find('button');
      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });

      await trigger.trigger('keydown', { key: 'Enter' });
      expect(dropdown.props('open')).toBe(true);

      await trigger.trigger('keydown', { key: 'Enter' });
      expect(dropdown.props('open')).toBe(false);

      await trigger.trigger('keydown', { key: ' ' });
      expect(dropdown.props('open')).toBe(true);
    });

    it('closes dropdown on Escape key and stops propagation', async () => {
      wrapper = mountComboBox();
      const trigger = wrapper.find('button');
      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });

      await trigger.trigger('click');
      expect(dropdown.props('open')).toBe(true);

      const stopPropagationSpy = vi.fn();
      await trigger.trigger('keydown', {
        key: 'Escape',
        stopPropagation: stopPropagationSpy,
      });

      expect(dropdown.props('open')).toBe(false);
      expect(stopPropagationSpy).toHaveBeenCalled();
    });
  });

  describe('Keyboard Navigation inside Dropdown', () => {
    it('filters options when typing inside search input', async () => {
      wrapper = mountComboBox();
      await wrapper.find('button').trigger('click');

      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });
      const searchInput = dropdown.find('input[type="search"]');

      await searchInput.setValue('Sales');
      await nextTick();

      expect(dropdown.props('options')).toEqual([
        { value: 'sales', label: 'Sales Department' },
      ]);
    });

    it('navigates with ArrowDown/ArrowUp and selects with Enter key', async () => {
      wrapper = mountComboBox();
      await wrapper.find('button').trigger('click');

      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });
      const searchInput = dropdown.find('input[type="search"]');

      // First item is highlighted by default (index 0: support).
      // Press ArrowDown to move to index 1: sales.
      await searchInput.trigger('keydown', { key: 'ArrowDown' });
      await searchInput.trigger('keydown', { key: 'Enter' });

      expect(wrapper.emitted('update:modelValue')?.[0]).toEqual(['sales']);
      expect(dropdown.props('open')).toBe(false);
    });

    it('closes dropdown and stops propagation when pressing Escape in search input', async () => {
      wrapper = mountComboBox();
      await wrapper.find('button').trigger('click');

      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });
      const searchInput = dropdown.find('input[type="search"]');

      const stopPropagationSpy = vi.fn();
      await searchInput.trigger('keydown', {
        key: 'Escape',
        stopPropagation: stopPropagationSpy,
      });

      expect(dropdown.props('open')).toBe(false);
      expect(stopPropagationSpy).toHaveBeenCalled();
    });
  });

  describe('Disabled State', () => {
    it('does not open when disabled', async () => {
      wrapper = mountComboBox({ disabled: true });
      const trigger = wrapper.find('button');
      const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });

      await trigger.trigger('click');
      expect(dropdown.props('open')).toBe(false);

      await trigger.trigger('keydown', { key: 's' });
      expect(dropdown.props('open')).toBe(false);

      await trigger.trigger('keydown', { key: 'ArrowDown' });
      expect(dropdown.props('open')).toBe(false);
    });
  });
});
