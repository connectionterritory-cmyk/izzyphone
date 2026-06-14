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

  // ── Helpers ─────────────────────────────────────────────

  function esc(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function getInitials(name) {
    const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return '?';
    if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
    return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
  }

  function avatarColor(name) {
    const palette = ['#1a3a6b', '#0f766e', '#6d28d9', '#b45309', '#be185d', '#0369a1'];
    let h = 0;
    for (const c of String(name || '')) h = (h * 31 + c.charCodeAt(0)) & 0xffff;
    return palette[h % palette.length];
  }

  function renderAvatar(user, size) {
    const name = user?.nombre || 'U';
    const initials = getInitials(name);
    const photoUrl = user?.photoUrl || user?.avatarUrl || null;
    const bg = avatarColor(name);
    const cls = `user-avatar user-avatar--${size}`;

    if (photoUrl) {
      const safe = esc(photoUrl);
      const safeInit = esc(initials);
      return `<div class="${cls}" style="background:${bg}" aria-label="${esc(name)}">` +
        `<img class="user-avatar-img" src="${safe}" alt="${safeInit}" ` +
        `onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">` +
        `<span class="user-avatar-initials" style="display:none">${safeInit}</span>` +
        `</div>`;
    }
    return `<div class="${cls}" style="background:${bg}" aria-label="${esc(name)}">` +
      `<span class="user-avatar-initials">${esc(initials)}</span>` +
      `</div>`;
  }

  // ── SVG icons ────────────────────────────────────────────

  const ICON_PERSON = `<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path d="M10 10a4 4 0 100-8 4 4 0 000 8zm-7 8a7 7 0 1114 0H3z"/></svg>`;
  const ICON_LOGOUT = `<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M3 4.25A2.25 2.25 0 015.25 2h5.5A2.25 2.25 0 0113 4.25v2a.75.75 0 01-1.5 0v-2a.75.75 0 00-.75-.75h-5.5a.75.75 0 00-.75.75v11.5c0 .414.336.75.75.75h5.5a.75.75 0 00.75-.75v-2a.75.75 0 011.5 0v2A2.25 2.25 0 0110.75 18h-5.5A2.25 2.25 0 013 15.75V4.25z" clip-rule="evenodd"/><path fill-rule="evenodd" d="M6 10a.75.75 0 01.75-.75h9.546l-1.048-.943a.75.75 0 111.004-1.114l2.5 2.25a.75.75 0 010 1.114l-2.5 2.25a.75.75 0 11-1.004-1.114l1.048-.943H6.75A.75.75 0 016 10z" clip-rule="evenodd"/></svg>`;
  const ICON_CARET = `<svg class="user-menu-caret" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 10.5L3 5.5h10z"/></svg>`;
  const ICON_CAMERA = `<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M1 8a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 018.07 3h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0016.07 6H17a2 2 0 012 2v7a2 2 0 01-2 2H3a2 2 0 01-2-2V8zm13.5 3a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0zM10 14a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"/></svg>`;

  // ── Dropdown HTML (shared between sidebar and mobile) ────

  function renderDropdownItems(prefix, userName, userRole) {
    return `
      <div class="user-menu-hd">
        <div class="user-menu-hd-name">${esc(userName)}</div>
        <div class="user-menu-hd-role">${esc(userRole)}</div>
      </div>
      <div class="user-menu-divider"></div>
      <button class="user-menu-item" type="button" id="${prefix}ProfileBtn" role="menuitem">
        ${ICON_PERSON}<span>Mi perfil</span>
      </button>
      <button class="user-menu-item user-menu-item--danger" type="button" id="${prefix}LogoutBtn" role="menuitem">
        ${ICON_LOGOUT}<span>Cerrar sesi&oacute;n</span>
      </button>`;
  }

  // ── Sidebar nav groups ───────────────────────────────────

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

  // ── Mobile bottom nav ────────────────────────────────────

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

  // ── Logout ───────────────────────────────────────────────

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

  // ── Profile modal ────────────────────────────────────────

  function openProfileModal(user) {
    const existing = document.getElementById('izzyProfileModal');
    if (existing) existing.remove();

    const name = user?.nombre || 'Usuario';
    const email = user?.email || '';
    const role = user?.rol === 'admin' ? 'Administrador' : user?.rol ? 'Agente' : 'Invitado';

    const modal = document.createElement('div');
    modal.id = 'izzyProfileModal';
    modal.className = 'profile-modal';
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-label', 'Mi perfil');
    modal.innerHTML = `
      <div class="profile-modal-backdrop"></div>
      <div class="profile-modal-inner">
        <button class="profile-modal-close" type="button" aria-label="Cerrar">&times;</button>
        <div class="profile-modal-avatar-wrap">
          ${renderAvatar(user, 'lg')}
          <button class="profile-avatar-change" type="button" title="Disponible próximamente">
            ${ICON_CAMERA}<span>Cambiar foto</span>
          </button>
        </div>
        <div class="profile-modal-name">${esc(name)}</div>
        <div class="profile-modal-role">${esc(role)}</div>
        ${email ? `<div class="profile-modal-email">${esc(email)}</div>` : ''}
        <p class="profile-modal-note">La carga de foto estará disponible próximamente (Supabase Storage).</p>
      </div>
    `;

    document.body.appendChild(modal);
    requestAnimationFrame(() => modal.classList.add('profile-modal--open'));

    function closeModal() {
      modal.classList.remove('profile-modal--open');
      setTimeout(() => { if (modal.parentNode) modal.remove(); }, 220);
    }

    modal.querySelector('.profile-modal-close').addEventListener('click', closeModal);
    modal.querySelector('.profile-modal-backdrop').addEventListener('click', closeModal);
    document.addEventListener('keydown', function onKey(e) {
      if (e.key === 'Escape') { closeModal(); document.removeEventListener('keydown', onKey); }
    });
  }

  // ── Main render ──────────────────────────────────────────

  window.renderIzzyNavigation = function renderIzzyNavigation(options) {
    const mount = document.getElementById(options.mountId || 'appNav');
    if (!mount) return;

    const user = options.user || null;
    const userName = user?.nombre || 'Invitado';
    const userRole = user?.rol === 'admin' ? 'Administrador' : user?.rol ? 'Agente' : 'Sesión no iniciada';

    mount.innerHTML = `
      <div class="app-shell">

        <!-- Sidebar (desktop) -->
        <aside class="app-sidebar">
          <div class="app-sidebar-inner">
            <div class="app-brand">
              <div class="app-brand-mark">
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M1.5 8.5C5.2 4.8 10.4 3 12 3s6.8 1.8 10.5 5.5L21 10c-3-3-5.7-5-9-5s-6 2-9 5l-1.5-1.5zM12 7c2.4 0 4.6.9 6.2 2.4L16.8 11C15.6 9.8 13.9 9 12 9s-3.6.8-4.8 2L5.8 9.4C7.4 7.9 9.6 7 12 7zm0 4c1.1 0 2.1.4 2.8 1.2L12 15l-2.8-2.8C9.9 11.4 10.9 11 12 11zm0 4l1.5 1.5L12 18l-1.5-1.5L12 15z"/></svg>
              </div>
              <div class="app-brand-copy">
                <div class="app-brand-title">Izzy Communications</div>
                <div class="app-brand-sub">Portal CRM</div>
              </div>
            </div>

            ${renderSidebarGroups(options)}
            <div class="app-sidebar-spacer"></div>

            <!-- Sidebar user profile -->
            <div class="app-sidebar-footer">
              <div class="user-profile" id="sidebarProfile">
                <button class="user-menu" type="button" id="sidebarUserBtn"
                        aria-expanded="false" aria-haspopup="true">
                  ${renderAvatar(user, 'md')}
                  <div class="user-menu-info">
                    <div class="user-menu-name">${esc(userName)}</div>
                    <div class="user-menu-role">${esc(userRole)}</div>
                  </div>
                  ${ICON_CARET}
                </button>
                <div class="user-menu-dropdown user-menu-dropdown--up" id="sidebarDropdown" role="menu">
                  ${renderDropdownItems('sidebar', userName, userRole)}
                </div>
              </div>
            </div>

          </div>
        </aside>

        <!-- Mobile header -->
        <div class="app-mobile-header">
          <div class="app-mobile-title">
            <strong>${esc(options.mobileTitle || options.pageTitle || 'Izzy Communications')}</strong>
            <span>Izzy Communications</span>
          </div>
          <div class="mobile-user-profile" id="mobileUserProfile">
            <button class="mobile-user-btn" type="button" id="mobileUserBtn"
                    aria-expanded="false" aria-haspopup="true"
                    aria-label="Menú de usuario">
              ${renderAvatar(user, 'sm')}
            </button>
            <div class="user-menu-dropdown user-menu-dropdown--mobile" id="mobileDropdown" role="menu">
              ${renderDropdownItems('mobile', userName, userRole)}
            </div>
          </div>
        </div>

        <!-- Mobile bottom nav -->
        <nav class="mobile-bottom-nav">
          ${renderMobileLinks(options)}
        </nav>

      </div>
    `;

    // ── Wire dropdowns ───────────────────────────────────

    const sidebarBtn = document.getElementById('sidebarUserBtn');
    const sidebarDrop = document.getElementById('sidebarDropdown');
    const mobileBtn = document.getElementById('mobileUserBtn');
    const mobileDrop = document.getElementById('mobileDropdown');

    function closeAll() {
      [sidebarDrop, mobileDrop].forEach(function (d) {
        if (d) d.classList.remove('open');
      });
      [sidebarBtn, mobileBtn].forEach(function (b) {
        if (b) b.setAttribute('aria-expanded', 'false');
      });
    }

    function toggleDrop(btn, drop) {
      const wasOpen = drop.classList.contains('open');
      closeAll();
      if (!wasOpen) {
        drop.classList.add('open');
        btn.setAttribute('aria-expanded', 'true');
      }
    }

    if (sidebarBtn && sidebarDrop) {
      sidebarBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        toggleDrop(sidebarBtn, sidebarDrop);
      });
    }

    if (mobileBtn && mobileDrop) {
      mobileBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        toggleDrop(mobileBtn, mobileDrop);
      });
    }

    document.addEventListener('click', closeAll);

    // Prevent clicks inside a dropdown from closing it
    [sidebarDrop, mobileDrop].forEach(function (d) {
      if (d) d.addEventListener('click', function (e) { e.stopPropagation(); });
    });

    // ── Profile buttons ──────────────────────────────────

    ['sidebarProfileBtn', 'mobileProfileBtn'].forEach(function (id) {
      const el = document.getElementById(id);
      if (el) {
        el.addEventListener('click', function () {
          closeAll();
          openProfileModal(user);
        });
      }
    });

    // ── Logout buttons ───────────────────────────────────

    ['sidebarLogoutBtn', 'mobileLogoutBtn'].forEach(function (id) {
      const el = document.getElementById(id);
      if (el) {
        el.addEventListener('click', function () {
          runLogout(options);
        });
      }
    });

    document.body.classList.add('has-app-shell');
  };
})();
