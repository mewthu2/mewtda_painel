(function () {
  var scriptEl = document.currentScript;
  if (!scriptEl) return;

  var token = scriptEl.getAttribute('data-token');
  if (!token) return;

  var origin = new URL(scriptEl.src).origin;
  var storageKey = 'mewtda_popup_dismissed_' + token;

  function getDismissedAt() {
    try {
      var raw = window.localStorage.getItem(storageKey);
      return raw ? parseInt(raw, 10) : null;
    } catch (e) {
      return null;
    }
  }

  function setDismissedNow() {
    try {
      window.localStorage.setItem(storageKey, String(Date.now()));
    } catch (e) {
      /* localStorage indisponível (ex.: modo privado) -- ignora */
    }
  }

  function shouldSkip(reappearAfterHours) {
    var dismissedAt = getDismissedAt();
    if (!dismissedAt) return false;
    var elapsedHours = (Date.now() - dismissedAt) / (1000 * 60 * 60);
    return elapsedHours < reappearAfterHours;
  }

  function isValidEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }

  var POPUP_CSS = '' +
    '.mewtda-popup-overlay{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:2147483000;padding:16px;}' +
    '.mewtda-popup{position:relative;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,.3);font-family:Arial,Helvetica,sans-serif;display:flex;max-height:90vh;}' +
    '.mewtda-popup--template_1{flex-direction:column;text-align:center;}' +
    '.mewtda-popup--template_1 .mewtda-popup__image img{width:100%;display:block;max-height:220px;object-fit:cover;}' +
    '.mewtda-popup--template_2{flex-direction:row;}' +
    '.mewtda-popup--template_2 .mewtda-popup__image{width:45%;order:1;}' +
    '.mewtda-popup--template_2 .mewtda-popup__content{order:2;}' +
    '.mewtda-popup--template_3{flex-direction:row;}' +
    '.mewtda-popup--template_3 .mewtda-popup__image{width:45%;order:2;}' +
    '.mewtda-popup--template_3 .mewtda-popup__content{order:1;}' +
    '.mewtda-popup--template_2 .mewtda-popup__image img,.mewtda-popup--template_3 .mewtda-popup__image img{width:100%;height:100%;object-fit:cover;display:block;}' +
    '.mewtda-popup--template_4{flex-direction:column;}' +
    '.mewtda-popup--small{width:360px;}' +
    '.mewtda-popup--medium{width:480px;}' +
    '.mewtda-popup--large{width:640px;}' +
    '.mewtda-popup__content{padding:24px;flex:1;overflow-y:auto;}' +
    '.mewtda-popup__title{margin:0 0 8px;font-size:22px;color:#111;}' +
    '.mewtda-popup__description{margin:0 0 16px;font-size:14px;color:#555;}' +
    '.mewtda-popup__form{display:flex;flex-direction:column;gap:10px;}' +
    '.mewtda-popup__input{padding:10px 12px;border:1px solid #ccc;border-radius:6px;font-size:14px;}' +
    '.mewtda-popup__submit{background:var(--mewtda-accent,#7c3aed);color:#fff;border:none;border-radius:6px;padding:12px;font-size:15px;font-weight:600;cursor:pointer;}' +
    '.mewtda-popup__submit:disabled{opacity:.6;cursor:default;}' +
    '.mewtda-popup__error{color:#c5221f;font-size:13px;}' +
    '.mewtda-popup__close{position:absolute;top:8px;right:8px;background:rgba(0,0,0,.08);border:none;border-radius:50%;width:28px;height:28px;font-size:18px;line-height:1;cursor:pointer;z-index:1;}' +
    '.mewtda-popup__success-title{font-size:18px;font-weight:700;margin:0 0 8px;}' +
    '.mewtda-popup__coupon{display:inline-block;padding:10px 16px;border:2px dashed var(--mewtda-accent,#7c3aed);border-radius:8px;font-size:18px;font-weight:700;color:var(--mewtda-accent,#7c3aed);}' +
    '@media(max-width:480px){.mewtda-popup--template_2,.mewtda-popup--template_3{flex-direction:column;}' +
    '.mewtda-popup--small,.mewtda-popup--medium,.mewtda-popup--large{width:100%;max-width:360px;}}';

  function injectStyles() {
    if (document.getElementById('mewtda-popup-styles')) return;
    var style = document.createElement('style');
    style.id = 'mewtda-popup-styles';
    style.textContent = POPUP_CSS;
    document.head.appendChild(style);
  }

  function renderModal(config) {
    injectStyles();

    var overlay = document.createElement('div');
    overlay.className = 'mewtda-popup-overlay';

    var modal = document.createElement('div');
    modal.className = 'mewtda-popup mewtda-popup--' + config.template + ' mewtda-popup--' + config.size;
    modal.style.setProperty('--mewtda-accent', config.accent_color || '#7c3aed');

    var showImage = !!config.image_url && config.template !== 'template_4';

    modal.innerHTML =
      '<button type="button" class="mewtda-popup__close" aria-label="Fechar">&times;</button>' +
      (showImage ? '<div class="mewtda-popup__image"><img alt=""></div>' : '') +
      '<div class="mewtda-popup__content">' +
        '<h2 class="mewtda-popup__title"></h2>' +
        (config.description ? '<p class="mewtda-popup__description"></p>' : '') +
        '<form class="mewtda-popup__form">' +
          '<input type="text" name="name" placeholder="Seu nome" required class="mewtda-popup__input">' +
          '<input type="email" name="email" placeholder="Seu e-mail" required class="mewtda-popup__input">' +
          '<input type="tel" name="phone" placeholder="Seu telefone" required class="mewtda-popup__input">' +
          '<div class="mewtda-popup__error" hidden></div>' +
          '<button type="submit" class="mewtda-popup__submit"></button>' +
        '</form>' +
        '<div class="mewtda-popup__success" hidden>' +
          '<p class="mewtda-popup__success-title">Cadastro realizado!</p>' +
          '<p class="mewtda-popup__coupon"></p>' +
        '</div>' +
      '</div>';

    modal.querySelector('.mewtda-popup__title').textContent = config.title || '';
    if (config.description) modal.querySelector('.mewtda-popup__description').textContent = config.description;
    modal.querySelector('.mewtda-popup__submit').textContent = config.button_text || 'Cadastrar';
    if (showImage) modal.querySelector('.mewtda-popup__image img').src = config.image_url;

    overlay.appendChild(modal);
    document.body.appendChild(overlay);

    function dismiss() {
      setDismissedNow();
      overlay.remove();
    }

    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) dismiss();
    });
    modal.querySelector('.mewtda-popup__close').addEventListener('click', dismiss);

    var form = modal.querySelector('.mewtda-popup__form');
    var errorEl = modal.querySelector('.mewtda-popup__error');

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      errorEl.hidden = true;

      var name = form.name.value.trim();
      var email = form.email.value.trim();
      var phone = form.phone.value.trim();

      if (!name || !isValidEmail(email) || !phone) {
        errorEl.textContent = 'Preencha nome, e-mail e telefone corretamente.';
        errorEl.hidden = false;
        return;
      }

      var submitBtn = form.querySelector('.mewtda-popup__submit');
      submitBtn.disabled = true;

      fetch(origin + '/widget/popup/submissions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: token, name: name, email: email, phone: phone })
      })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          if (data.coupon_code) {
            form.hidden = true;
            var successEl = modal.querySelector('.mewtda-popup__success');
            successEl.hidden = false;
            successEl.querySelector('.mewtda-popup__coupon').textContent = data.coupon_code;
            setDismissedNow();
          } else {
            errorEl.textContent = 'Não foi possível enviar seu cadastro. Tente novamente.';
            errorEl.hidden = false;
            submitBtn.disabled = false;
          }
        })
        .catch(function () {
          errorEl.textContent = 'Não foi possível enviar seu cadastro. Tente novamente.';
          errorEl.hidden = false;
          submitBtn.disabled = false;
        });
    });
  }

  fetch(origin + '/widget/popup/config?token=' + encodeURIComponent(token))
    .then(function (res) { return res.json(); })
    .then(function (config) {
      if (!config.active) return;
      if (shouldSkip(config.reappear_after_hours)) return;
      renderModal(config);
    })
    .catch(function () { /* falha ao buscar config -- não mostra nada */ });
})();
