(function () {
  const ICONS = {
    cotizador: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>`,
    leads: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><rect x="7" y="10" width="4" height="7" rx="1"/><rect x="15" y="4" width="4" height="13" rx="1"/></svg>`,
    orders: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"/><path d="M12 17.5v-11"/></svg>`,
    level: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="7"/><polyline points="8.21 13.89 7 23 12 20 17 23 15.79 13.88"/></svg>`,
    tree: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="16" y="16" width="6" height="6" rx="1"/><rect x="2" y="16" width="6" height="6" rx="1"/><rect x="9" y="2" width="6" height="6" rx="1"/><path d="M5 16v-3a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v3"/><path d="M12 8v3"/></svg>`,
    table: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2"/><path d="M6 12h.01M18 12h.01"/></svg>`,
    elite: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>`,
    progress: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/></svg>`,
    bonuses: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13"/><path d="M19 12v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7"/><path d="M7.5 8a2.5 2.5 0 0 1 0-5A4.8 8 0 0 1 12 8a4.8 8 0 0 1 4.5-5 2.5 2.5 0 0 1 0 5"/></svg>`,
    ambassadors: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m11 17 2 2a1 1 0 1 0 3-3"/><path d="m14 14 2.5 2.5a1 1 0 1 0 3-3l-3.88-3.88a3 3 0 0 0-4.24 0l-.88.88a1 1 0 1 1-3-3l2.81-2.81a5.79 5.79 0 0 1 7.06-.87l.47.28a2 2 0 0 0 1.42.25L21 4"/><path d="m21 3-6 6"/><path d="M21 3v6"/><path d="M21 3h-6"/><path d="M8.12 9.25 4.53 13.6a2 2 0 0 0 0 2.8l2.07 2.07a2 2 0 0 0 2.8 0l4.35-3.59"/></svg>`,
    users: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>`,
    admin: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>`,
    tutorial: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>`,
    chevronDown: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>`
  };

  const SIDEBAR_ITEMS = [
    {
      section: 'principal',
      label: 'Principal',
      items: [
        { key: 'cotizador', href: 'index.html', icon: ICONS.cotizador, text: 'Cotizador' },
        { key: 'leads', href: 'leads.html', icon: ICONS.leads, text: 'Leads' },
        { key: 'orders', href: 'orders.html', icon: ICONS.orders, text: 'Orders' }
      ]
    },
    {
      section: 'compensation',
      label: 'Plan de Compensacion',
      items: [
        { key: 'comp-level', href: 'compensation.html?tab=level', icon: ICONS.level, text: 'Mi Nivel' },
        { key: 'comp-tree', href: 'compensation.html?tab=tree', icon: ICONS.tree, text: 'Mi Arbol' },
        { key: 'comp-table', href: 'compensation.html?tab=table', icon: ICONS.table, text: 'Tabla de Comisiones' },
        { key: 'comp-elite', href: 'compensation.html?tab=elite', icon: ICONS.elite, text: 'Productor Elite' },
        { key: 'comp-progress', href: 'compensation.html?tab=progress', icon: ICONS.progress, text: 'Progreso de Carrera' },
        { key: 'comp-bonuses', href: 'compensation.html?tab=bonuses', icon: ICONS.bonuses, text: 'Bonos' },
        { key: 'comp-ambassadors', href: 'compensation.html?tab=ambassadors', icon: ICONS.ambassadors, text: 'Programa Embajador' }
      ]
    },
    {
      section: 'admin',
      label: 'Admin',
      items: [
        { key: 'users', href: 'users.html', icon: ICONS.users, text: 'Usuarios', adminOnly: true },
        { key: 'comp-admin', href: 'compensation.html?tab=admin', icon: ICONS.admin, text: 'Compensacion', adminOnly: true },
        { key: 'tutorial', href: 'tutorial.html', icon: ICONS.tutorial, text: 'Tutorial' }
      ]
    }
  ];

  const MOBILE_ITEMS = [
    { key: 'cotizador', href: 'index.html', icon: ICONS.cotizador, text: 'Cotizador' },
    { key: 'leads', href: 'leads.html', icon: ICONS.leads, text: 'Leads' },
    { key: 'orders', href: 'orders.html', icon: ICONS.orders, text: 'Orders' },
    { key: 'compensation', href: 'compensation.html', icon: ICONS.level, text: 'Compensacion' },
    { key: 'admin', href: 'users.html', icon: ICONS.users, text: 'Admin' }
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
      const allowedItems = group.items.filter((item) => !item.adminOnly || isAdmin);
      if (allowedItems.length === 0) return '';
      
      const isGroupActive = allowedItems.some(item => item.key === options.activeSidebar);
      // We will add logic in JS to toggle the 'collapsed' class on click
      const collapsedClass = isGroupActive ? '' : ' collapsed';

      const links = allowedItems
        .map((item) => {
          const href = item.key === 'tutorial' ? tutorialHref : item.href;
          const active = item.key === options.activeSidebar ? ' active' : '';
          return `<a class="app-sidebar-link${active}" href="${href}">
            <span class="app-sidebar-icon">${item.icon}</span>
            <span class="app-sidebar-text">${item.text}</span>
          </a>`;
        })
        .join('');

      return `<div class="app-sidebar-group${collapsedClass}">
        <button class="app-sidebar-label-btn" type="button">
          <span class="app-sidebar-label-text">${group.label}</span>
          <span class="app-sidebar-chevron">${ICONS.chevronDown}</span>
        </button>
        <div class="app-sidebar-links">
          ${links}
        </div>
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

    // ── Dropdowns & Collapse ─────────────────────────────
    
    // Group collapsibles
    document.querySelectorAll('.app-sidebar-label-btn').forEach(btn => {
      btn.addEventListener('click', function(e) {
        const group = e.currentTarget.closest('.app-sidebar-group');
        if (group) group.classList.toggle('collapsed');
      });
    });

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
