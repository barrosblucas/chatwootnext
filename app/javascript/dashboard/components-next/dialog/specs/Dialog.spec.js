import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import Dialog from '../Dialog.vue';

describe('Dialog.vue', () => {
  let wrapper;

  beforeAll(() => {
    if (typeof HTMLDialogElement !== 'undefined') {
      HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
        this.open = true;
      });
      HTMLDialogElement.prototype.close = vi.fn(function closeDialog() {
        this.open = false;
      });
    }
  });

  beforeEach(() => {
    wrapper?.unmount();
  });

  const mountDialog = (props = {}, options = {}) => {
    return mount(Dialog, {
      props: {
        title: 'Test Dialog',
        ...props,
      },
      slots: {
        default: '<div class="dialog-inner">Content</div>',
      },
      global: {
        stubs: {
          TeleportWithDirection: {
            template: '<div><slot /></div>',
          },
          OnClickOutside: {
            template: '<div><slot /></div>',
          },
          Button: {
            template: '<button><slot />{{ label }}</button>',
            props: ['label'],
          },
        },
      },
      ...options,
    });
  };

  it('renders default overflow classes when overflowVisible is false', () => {
    wrapper = mountDialog();
    wrapper.vm.open();

    const dialog = wrapper.find('dialog');
    expect(dialog.classes()).toContain('overflow-hidden');
    expect(dialog.classes()).not.toContain('overflow-visible');

    const form = wrapper.find('form');
    expect(form.classes()).toContain('overflow-hidden');
    expect(form.classes()).not.toContain('overflow-visible');

    const contentSlot = wrapper.find('.flex-1');
    expect(contentSlot.classes()).toContain('overflow-y-auto');
    expect(contentSlot.classes()).not.toContain('overflow-visible');
  });

  it('renders overflow-visible classes when overflowVisible is true', () => {
    wrapper = mountDialog({ overflowVisible: true });
    wrapper.vm.open();

    const dialog = wrapper.find('dialog');
    expect(dialog.classes()).toContain('overflow-visible');
    expect(dialog.classes()).not.toContain('overflow-hidden');

    const form = wrapper.find('form');
    expect(form.classes()).toContain('overflow-visible');
    expect(form.classes()).not.toContain('overflow-hidden');

    const contentSlot = wrapper.find('.flex-1');
    expect(contentSlot.classes()).toContain('overflow-visible');
    expect(contentSlot.classes()).not.toContain('overflow-y-auto');
  });

  it('renders overflow-y-auto on dialog when overflowYAuto is true and overflowVisible is false', () => {
    wrapper = mountDialog({ overflowYAuto: true, overflowVisible: false });
    wrapper.vm.open();

    const dialog = wrapper.find('dialog');
    expect(dialog.classes()).toContain('overflow-y-auto');
    expect(dialog.classes()).not.toContain('overflow-visible');
  });
});
