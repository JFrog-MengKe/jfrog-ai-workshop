/* Language dictionaries are loaded from locales/<language>.json. No external service. */
(() => {
  'use strict';
  const supported = ['zh-CN', 'zh-TW', 'en'];
  const state = { locale: 'zh-CN', messages: {}, onChange: null };
  const select = document.getElementById('languageSelect');
  let request = 0;
  state.t = source => Object.prototype.hasOwnProperty.call(state.messages, source)
    ? state.messages[source] : source;

  state.source = text => {
    for (const [key, value] of Object.entries(state.messages)) if (value === text) return key;
    return text;
  };

  function render() {
    document.documentElement.lang = state.locale;
    document.querySelectorAll('[data-i18n]').forEach(element => {
      element.textContent = state.t(element.dataset.i18n);
    });
    for (const attribute of ['alt', 'placeholder', 'aria-label', 'title']) {
      document.querySelectorAll('[data-i18n-' + attribute + ']').forEach(element => {
        element.setAttribute(attribute, state.t(element.getAttribute('data-i18n-' + attribute)));
      });
    }
    select.value = state.locale;
    if (state.onChange) state.onChange();
  }

  state.setLanguage = async locale => {
    if (!supported.includes(locale)) return;
    const version = ++request;
    select.disabled = true;
    try {
      const response = await fetch('locales/' + locale + '.json', { cache: 'no-store' });
      if (!response.ok) throw new Error('Language HTTP ' + response.status);
      const dictionary = await response.json();
      if (dictionary.locale !== locale || !dictionary.messages || typeof dictionary.messages !== 'object') {
        throw new Error('Invalid language configuration');
      }
      if (version !== request) return;
      state.locale = locale;
      state.messages = dictionary.messages;
      try { localStorage.setItem('workshop.language', locale); } catch {}
      render();
    } catch (error) {
      if (version !== request) return;
      select.value = state.locale;
      const toast = document.getElementById('toast');
      toast.textContent = state.t('语言加载失败，请重试。');
      toast.hidden = false;
      setTimeout(() => { toast.hidden = true; }, 4000);
      console.error('Could not load workshop language:', error.message);
    } finally {
      if (version === request) select.disabled = false;
    }
  };
  select.addEventListener('change', () => state.setLanguage(select.value));
  window.WorkshopI18n = state;
  let initial = 'zh-CN';
  try {
    const saved = localStorage.getItem('workshop.language');
    if (supported.includes(saved)) initial = saved;
  } catch {}
  state.ready = state.setLanguage(initial);
})();
