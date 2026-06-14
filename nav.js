(function () {
  const SIDEBAR_ITEMS = [
    {
      section: 'principal',
      label: 'Principal',
      items: [
        { key: 'cotizador', href: 'index.html', icon: '📋', text: 'Cotizador' },
        { key: 'leads', href: 'leads.html', icon: '📊', text: 'Leads' },
        { key: 'orders', href: 'orders.html', icon: '🧾', text: 'Orders' }
      ]
    },
    {
      section: 'admin',
      label: 'Admin',
      items: [
        { key: 'users', href: 'users.html', icon: '👥', text: 'Usuarios', adminOnly: true },
        { key: 'tutorial', href: 'tutorial.html', icon: '📖', text: 'Tutorial' }
      ]
    }
  ];

  const MOBILE_ITEMS = [
    { key: 'cotizador', href: 'index.html', icon: '📋', text: 'Cotizador' },
    { key: 'leads', href: 'leads.html', icon: '📊', text: 'Leads' },
    { key: 'orders', href: 'orders.html', icon: '🧾', text: 'Orders' },
    { key: 'admin', href: 'users.html', icon: '👥', text: 'Admin' }
  ];

  function esc(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function renderSidebarGroups(options) {
    const isAdmin = Boolean(options.isAdmin);
    const tutorialHref = options.tutorialHref || 'tutorial.html';

    return SIDEBAR_ITEMS.map((group) => {
      const links = group.items
        .filter((item) => !item.adminOnly || isAdmin)
        .map((item) => {
          const href = item.key === 'tutorial' ? tutorialHref : item.href;
          const active = item.key === options.activeSidebar ? ' active' : '';
          return `<a class="app-sidebar-link${active}" href="${href}"><span>${item.icon}</span><span>${item.text}</span></a>`;
        })
        .join('');

      return `<div class="app-sidebar-group">
        <div class="app-sidebar-label">${group.label}</div>
        ${links}
      </div>`;
    }).join('');
  }

  function renderMobileLinks(options) {
    const tutorialHref = options.tutorialHref || 'tutorial.html';
    return MOBILE_ITEMS.map((item) => {
      let href = item.href;
      if (item.key === 'admin' && options.mobileAdminHref) href = options.mobileAdminHref;
      if (item.key === 'admin' && options.activeSidebar === 'tutorial') href = tutorialHref;
      const active = item.key === options.activeMobile ? ' active' : '';
      return `<a class="mobile-bottom-link${active}" href="${href}">
        <span class="mobile-bottom-icon">${item.icon}</span>
        <span>${item.text}</span>
      </a>`;
    }).join('');
  }

  function defaultLogout() {
    try {
      localStorage.removeItem('izzy_session');
      localStorage.removeItem('izzy_restore');
    } catch {}
    window.location.href = 'index.html';
  }

  function runLogout(options) {
    if (typeof options.onLogout === 'function') {
      options.onLogout();
      return;
    }
    defaultLogout();
  }

  window.renderIzzyNavigation = function renderIzzyNavigation(options) {
    const mount = document.getElementById(options.mountId || 'appNav');
    if (!mount) return;

    const user = options.user || null;
    const userName = user?.nombre || 'Invitado';
    const userRole = user?.rol === 'admin' ? 'Administrador' : user?.rol ? 'Agente' : 'Sesión no iniciada';

    mount.innerHTML = `
      <div class="app-shell">
        <aside class="app-sidebar">
          <div class="app-sidebar-inner">
            <div class="app-brand">
              <div class="app-brand-mark">
                <svg viewBox="0 0 24 24"><path d="M1.5 8.5C5.2 4.8 10.4 3 12 3s6.8 1.8 10.5 5.5L21 10c-3-3-5.7-5-9-5s-6 2-9 5l-1.5-1.5zM12 7c2.4 0 4.6.9 6.2 2.4L16.8 11C15.6 9.8 13.9 9 12 9s-3.6.8-4.8 2L5.8 9.4C7.4 7.9 9.6 7 12 7zm0 4c1.1 0 2.1.4 2.8 1.2L12 15l-2.8-2.8C9.9 11.4 10.9 11 12 11zm0 4l1.5 1.5L12 18l-1.5-1.5L12 15z"/></svg>
              </div>
              <div class="app-brand-copy">
                <div class="app-brand-title">Izzy Communications</div>
                <div class="app-brand-sub">Portal CRM</div>
              </div>
            </div>
            ${renderSidebarGroups(options)}
            <div class="app-sidebar-spacer"></div>
            <div class="app-sidebar-footer">
              <div class="app-user-card">
                <div class="app-user-label">Usuario conectado</div>
                <div class="app-user-name">${esc(userName)}</div>
                <div class="app-user-role">${esc(userRole)}</div>
              </div>
              <button class="app-logout-btn" type="button" id="appLogoutBtn">${user ? '↪ Cerrar sesión' : '↪ Ir al login'}</button>
            </div>
          </div>
        </aside>
        <div class="app-mobile-header">
          <div class="app-mobile-title">
            <strong>${esc(options.mobileTitle || options.pageTitle || 'Izzy Communications')}</strong>
            <span>Izzy Communications</span>
          </div>
          <button class="app-mobile-logout" type="button" id="appMobileLogoutBtn">${user ? '↪ Salir' : 'Salir'}</button>
        </div>
        <nav class="mobile-bottom-nav">
          ${renderMobileLinks(options)}
        </nav>
      </div>
    `;

    const btn = document.getElementById('appLogoutBtn');
    if (btn) {
      btn.addEventListener('click', function () {
        runLogout(options);
      });
    }

    const mobileBtn = document.getElementById('appMobileLogoutBtn');
    if (mobileBtn) {
      mobileBtn.addEventListener('click', function () {
        runLogout(options);
      });
    }

    document.body.classList.add('has-app-shell');
  };
})();
