"use client";

import Link from "next/link";
import { createPortal } from "react-dom";
import { useEffect, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type RefObject } from "react";
import { visibleAdministrativeAreas } from "../lib/administrative";
import { buildSidebarNavigation, isSidebarNavigationItemActive, type SidebarNavigationItem as NavigationItem } from "../lib/sidebar-navigation";
import type { SessionProfile } from "../lib/session";
import { roleLabel, staffIdentity } from "../lib/staff-identity";
import { HpsmLogo } from "./hpsm-logo";
import { SidebarIcon } from "./sidebar-icon";
import { ThemeToggle } from "./theme-toggle";

type SidebarProps = {
  active: string;
  onCollapsedChange: (collapsed: boolean) => void;
  pathname: string;
  pendingCount: number;
  permissionCodes: string[];
  positionDisplayName: string | null;
  profile: SessionProfile;
};

type FlyoutPosition = { left: number; maxHeight: number; top: number };

const CLOSE_DELAY_MS = 180;
const DESKTOP_MENU_QUERY = "(min-width: 821px) and (hover: hover)";
const MOBILE_MENU_QUERY = "(max-width: 820px)";

export function AppSidebar({ active, onCollapsedChange, pathname, pendingCount, permissionCodes, positionDisplayName, profile }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [desktopMenu, setDesktopMenu] = useState(false);
  const [mobileMenu, setMobileMenu] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [openGroup, setOpenGroup] = useState<string | null>(null);
  const [pinnedGroup, setPinnedGroup] = useState<string | null>(null);
  const [flyoutPosition, setFlyoutPosition] = useState<FlyoutPosition | null>(null);
  const closeTimer = useRef<number | null>(null);
  const groupTriggerRef = useRef<HTMLButtonElement | null>(null);
  const firstFlyoutItemRef = useRef<HTMLAnchorElement | null>(null);
  const mobileTriggerRef = useRef<HTMLButtonElement | null>(null);
  const mobileCloseRef = useRef<HTMLButtonElement | null>(null);

  const navigationSections = useMemo(() => {
    const administrativeChildren = visibleAdministrativeAreas(permissionCodes).map((area) => ({ href: area.href, icon: area.id, id: area.id, label: area.label }));
    return buildSidebarNavigation(permissionCodes, pendingCount, administrativeChildren);
  }, [pendingCount, permissionCodes]);
  const navigation = useMemo(() => navigationSections.flatMap((section) => section.items), [navigationSections]);
  const userIdentity = staffIdentity(profile.passport, positionDisplayName ?? roleLabel(profile.role_code));
  const effectiveCollapsed = collapsed && !mobileMenu;

  useEffect(() => {
    const stored = window.localStorage.getItem(sidebarStorageKey(profile.user_id));
    const frame = window.requestAnimationFrame(() => setCollapsed(stored === "collapsed"));
    return () => window.cancelAnimationFrame(frame);
  }, [profile.user_id]);

  useEffect(() => {
    onCollapsedChange(effectiveCollapsed);
  }, [effectiveCollapsed, onCollapsedChange]);

  useEffect(() => {
    const media = window.matchMedia(DESKTOP_MENU_QUERY);
    const sync = () => {
      setDesktopMenu(media.matches);
      if (!media.matches) {
        clearCloseTimer();
        setOpenGroup(null);
        setPinnedGroup(null);
      }
    };
    sync();
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, []);

  useEffect(() => {
    const media = window.matchMedia(MOBILE_MENU_QUERY);
    const sync = () => {
      setMobileMenu(media.matches);
      if (!media.matches) setMobileOpen(false);
    };
    sync();
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, []);

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => setMobileOpen(false));
    return () => window.cancelAnimationFrame(frame);
  }, [pathname]);

  useEffect(() => {
    if (!mobileMenu || !mobileOpen) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const frame = window.requestAnimationFrame(() => mobileCloseRef.current?.focus());
    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      event.preventDefault();
      setOpenGroup(null);
      setPinnedGroup(null);
      setFlyoutPosition(null);
      setMobileOpen(false);
      window.requestAnimationFrame(() => mobileTriggerRef.current?.focus());
    }
    window.addEventListener("keydown", onKeyDown);
    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  }, [mobileMenu, mobileOpen]);

  useEffect(() => () => clearCloseTimer(), []);

  useEffect(() => {
    if (!desktopMenu || !openGroup) return;
    const reposition = () => {
      const item = navigation.find((candidate) => candidate.id === openGroup);
      if (groupTriggerRef.current && item) updateFlyoutPosition(groupTriggerRef.current, item);
    };
    reposition();
    window.addEventListener("resize", reposition);
    window.addEventListener("scroll", reposition, true);
    return () => {
      window.removeEventListener("resize", reposition);
      window.removeEventListener("scroll", reposition, true);
    };
  }, [desktopMenu, navigation, openGroup]);

  useEffect(() => {
    if (!openGroup) return;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      event.preventDefault();
      clearCloseTimer();
      setOpenGroup(null);
      setPinnedGroup(null);
      groupTriggerRef.current?.focus();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [openGroup]);

  function clearCloseTimer() {
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
    closeTimer.current = null;
  }

  function updateFlyoutPosition(trigger: HTMLButtonElement, item: NavigationItem) {
    const rect = trigger.getBoundingClientRect();
    const availableHeight = Math.max(96, window.innerHeight - 24);
    const estimatedHeight = Math.min(82 + ((item.children?.length ?? 0) + (item.href ? 1 : 0)) * 41, availableHeight);
    const safeTop = Math.max(12, Math.min(rect.top, window.innerHeight - estimatedHeight - 12));
    setFlyoutPosition({
      left: Math.max(12, Math.min(rect.right + 12, window.innerWidth - 308)),
      maxHeight: Math.max(96, window.innerHeight - safeTop - 12),
      top: safeTop,
    });
  }

  function openDesktopGroup(item: NavigationItem, trigger: HTMLButtonElement) {
    clearCloseTimer();
    groupTriggerRef.current = trigger;
    updateFlyoutPosition(trigger, item);
    setOpenGroup(item.id);
  }

  function scheduleGroupClose() {
    if (pinnedGroup) return;
    clearCloseTimer();
    closeTimer.current = window.setTimeout(() => {
      setOpenGroup(null);
      setFlyoutPosition(null);
    }, CLOSE_DELAY_MS);
  }

  function toggleGroup(item: NavigationItem, trigger: HTMLButtonElement) {
    groupTriggerRef.current = trigger;
    if (!desktopMenu) {
      setOpenGroup((current) => current === item.id ? null : item.id);
      return;
    }
    if (openGroup === item.id && pinnedGroup === item.id) {
      clearCloseTimer();
      setOpenGroup(null);
      setPinnedGroup(null);
      return;
    }
    openDesktopGroup(item, trigger);
    setPinnedGroup(item.id);
  }

  function onGroupKeyDown(event: ReactKeyboardEvent<HTMLButtonElement>, item: NavigationItem) {
    if (event.key === "Escape") {
      event.preventDefault();
      setOpenGroup(null);
      setPinnedGroup(null);
      return;
    }
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    toggleGroup(item, event.currentTarget);
    if (desktopMenu) {
      window.requestAnimationFrame(() => firstFlyoutItemRef.current?.focus());
    }
  }

  function setSidebarCollapsed(next: boolean) {
    setCollapsed(next);
    window.localStorage.setItem(sidebarStorageKey(profile.user_id), next ? "collapsed" : "expanded");
  }

  function closeNavigationOverlay() {
    clearCloseTimer();
    setOpenGroup(null);
    setPinnedGroup(null);
    setFlyoutPosition(null);
    setMobileOpen(false);
  }

  function closeMobileNavigation(restoreFocus = false) {
    closeNavigationOverlay();
    if (restoreFocus) window.requestAnimationFrame(() => mobileTriggerRef.current?.focus());
  }

  return (
    <>
      <header className="sidebar-mobile-bar">
        <span className="sidebar-mobile-brand"><HpsmLogo compact /></span>
        <button
          aria-controls="professional-navigation"
          aria-expanded={mobileOpen}
          className="sidebar-mobile-trigger"
          onClick={() => setMobileOpen(true)}
          ref={mobileTriggerRef}
          type="button"
        >
          <span aria-hidden="true" className="sidebar-mobile-trigger-icon"><i /><i /><i /></span>
          <span>Menu</span>
        </button>
      </header>
      <button
        aria-label="Fechar menu de navegação"
        className="sidebar-mobile-backdrop"
        data-open={mobileOpen}
        onClick={() => closeMobileNavigation(true)}
        tabIndex={mobileOpen ? 0 : -1}
        type="button"
      />
      <aside
        aria-hidden={mobileMenu ? !mobileOpen : undefined}
        aria-label={mobileMenu ? "Menu principal" : undefined}
        aria-modal={mobileMenu ? true : undefined}
        className="sidebar sidebar-modern"
        data-collapsed={effectiveCollapsed}
        data-mobile-open={mobileOpen}
        id="professional-navigation"
        inert={mobileMenu && !mobileOpen ? true : undefined}
        role={mobileMenu ? "dialog" : undefined}
      >
      <div className="sidebar-brand-row">
        <div className="sidebar-brand" aria-label="Hospital Santa Marcelina">
          <HpsmLogo compact={!effectiveCollapsed} markOnly={effectiveCollapsed} />
        </div>
        <button
          aria-label={effectiveCollapsed ? "Expandir menu lateral" : "Recolher menu lateral"}
          aria-pressed={effectiveCollapsed}
          className="sidebar-collapse-control"
          onClick={() => setSidebarCollapsed(!collapsed)}
          title={effectiveCollapsed ? "Expandir menu" : "Recolher menu"}
          type="button"
        >
          <span aria-hidden="true">{effectiveCollapsed ? "›" : "‹"}</span>
        </button>
        <button
          aria-label="Fechar menu"
          className="sidebar-mobile-close"
          onClick={() => closeMobileNavigation(true)}
          ref={mobileCloseRef}
          type="button"
        >
          <span aria-hidden="true">×</span>
        </button>
      </div>

      <nav className="sidebar-nav" aria-label="Navegação principal">
        {navigationSections.map((section) => <NavigationSection
          active={active}
          collapsed={effectiveCollapsed}
          desktopMenu={desktopMenu}
          items={section.items}
          key={section.id}
          onGroupEnter={openDesktopGroup}
          onGroupKeyDown={onGroupKeyDown}
          onGroupLeave={scheduleGroupClose}
          onGroupToggle={toggleGroup}
          onNavigate={closeNavigationOverlay}
          openGroup={openGroup}
          pathname={pathname}
          title={section.label}
        />)}
      </nav>

      <div className="sidebar-theme"><ThemeToggle userId={profile.user_id} /></div>
      <div className="sidebar-user">
        <span aria-label={`${profile.display_name} · ${userIdentity}`} className="user-avatar" data-tooltip={effectiveCollapsed ? `${profile.display_name} · ${userIdentity}` : undefined} tabIndex={effectiveCollapsed ? 0 : undefined} title={`${profile.display_name} · ${userIdentity}`}>{initials(profile.display_name)}</span>
        <div className="sidebar-user-copy" title={`${profile.display_name} · ${userIdentity}`}><strong>{profile.display_name}</strong><span>{userIdentity}</span></div>
        <form action="/api/auth/logout" method="post"><button type="submit" aria-label="Sair do sistema" title="Sair do sistema">↗</button></form>
      </div>

      {desktopMenu && openGroup ? renderDesktopFlyout({
        flyoutPosition,
        firstFlyoutItemRef,
        item: navigation.find((item) => item.id === openGroup),
        onClose: scheduleGroupClose,
        onEnter: clearCloseTimer,
        onNavigate: closeNavigationOverlay,
        pathname,
      }) : null}
      </aside>
    </>
  );
}

function NavigationSection({ active, collapsed, desktopMenu, items, onGroupEnter, onGroupKeyDown, onGroupLeave, onGroupToggle, onNavigate, openGroup, pathname, title }: {
  active: string;
  collapsed: boolean;
  desktopMenu: boolean;
  items: NavigationItem[];
  onGroupEnter: (item: NavigationItem, trigger: HTMLButtonElement) => void;
  onGroupKeyDown: (event: ReactKeyboardEvent<HTMLButtonElement>, item: NavigationItem) => void;
  onGroupLeave: () => void;
  onGroupToggle: (item: NavigationItem, trigger: HTMLButtonElement) => void;
  onNavigate: () => void;
  openGroup: string | null;
  pathname: string;
  title: string;
}) {
  if (!items.length) return null;
  return <div className="sidebar-nav-section">
    <p>{title}</p>
    {items.map((item) => {
      const isGroup = Boolean(item.children?.length);
      const isActive = isSidebarNavigationItemActive(item, active, pathname);
      const isOpen = openGroup === item.id;
      if (!isGroup) {
        return <Link aria-current={isActive ? "page" : undefined} aria-label={collapsed ? item.label : undefined} className="sidebar-nav-item" data-active={isActive} data-tooltip={collapsed ? item.label : undefined} href={item.href!} key={item.id} onClick={onNavigate} prefetch={shouldPrefetchRoute(item.href!)}>
          <span className="sidebar-nav-icon"><SidebarIcon name={item.icon} /></span><span className="sidebar-nav-label">{item.label}</span>{item.count ? <em className="nav-count" aria-label={`${item.count} decisões pendentes`}>{item.count}</em> : null}
        </Link>;
      }
      return <div className="sidebar-group" key={item.id} onMouseEnter={(event) => desktopMenu && onGroupEnter(item, event.currentTarget.querySelector<HTMLButtonElement>("button")!)} onMouseLeave={() => desktopMenu && onGroupLeave()}>
        <button
          aria-controls={`sidebar-submenu-${item.id}`}
          aria-expanded={isOpen}
          aria-haspopup="true"
          aria-label={collapsed ? item.label : undefined}
          className="sidebar-nav-item sidebar-group-trigger"
          data-active={isActive}
          data-tooltip={collapsed ? item.label : undefined}
          onClick={(event) => onGroupToggle(item, event.currentTarget)}
          onKeyDown={(event) => onGroupKeyDown(event, item)}
          type="button"
        >
          <span className="sidebar-nav-icon"><SidebarIcon name={item.icon} /></span><span className="sidebar-nav-label">{item.label}</span>{item.count ? <em className="nav-count" aria-label={`${item.count} decisões pendentes`}>{item.count}</em> : null}<span className="sidebar-group-chevron" aria-hidden="true">›</span>
        </button>
        {!desktopMenu && isOpen ? <InlineSubmenu item={item} onNavigate={onNavigate} pathname={pathname} /> : null}
      </div>;
    })}
  </div>;
}

function InlineSubmenu({ item, onNavigate, pathname }: { item: NavigationItem; onNavigate: () => void; pathname: string }) {
  return <div className="sidebar-inline-submenu" id={`sidebar-submenu-${item.id}`}>
    {item.href ? <Link aria-current={pathname === item.href ? "page" : undefined} data-active={pathname === item.href} href={item.href} onClick={onNavigate} prefetch={shouldPrefetchRoute(item.href)}><span><SidebarIcon name="dashboard" /></span>{item.overviewLabel ?? item.label}</Link> : null}
    {item.children!.map((child) => <Link aria-current={isPathActive(pathname, child.href) ? "page" : undefined} data-active={isPathActive(pathname, child.href)} href={child.href} key={child.id} onClick={onNavigate} prefetch={shouldPrefetchRoute(child.href)}><span><SidebarIcon name={child.icon} /></span>{child.label}</Link>)}
  </div>;
}

function renderDesktopFlyout({ flyoutPosition, firstFlyoutItemRef, item, onClose, onEnter, onNavigate, pathname }: {
  flyoutPosition: FlyoutPosition | null;
  firstFlyoutItemRef: RefObject<HTMLAnchorElement | null>;
  item: NavigationItem | undefined;
  onClose: () => void;
  onEnter: () => void;
  onNavigate: () => void;
  pathname: string;
}) {
  if (!item?.children?.length || !flyoutPosition) return null;
  const panel = <div
    className="sidebar-flyout-layer"
    onMouseEnter={onEnter}
    onMouseLeave={onClose}
    style={{ left: flyoutPosition.left, maxHeight: flyoutPosition.maxHeight, top: flyoutPosition.top }}
  >
    <span aria-hidden="true" className="sidebar-flyout-bridge" />
    <section
      aria-label={`Submenu ${item.label}`}
      className="sidebar-flyout"
      id={`sidebar-submenu-${item.id}`}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) onClose();
      }}
    >
      <div className="sidebar-flyout-heading"><span><SidebarIcon name={item.icon} /></span><div><strong>{item.label}</strong><small>Áreas disponíveis</small></div></div>
      <nav>
        {item.href ? <Link aria-current={pathname === item.href ? "page" : undefined} data-active={pathname === item.href} href={item.href} onClick={onNavigate} prefetch={shouldPrefetchRoute(item.href)} ref={firstFlyoutItemRef}><span><SidebarIcon name="dashboard" /></span>{item.overviewLabel ?? item.label}</Link> : null}
        {item.children.map((child, index) => <Link aria-current={isPathActive(pathname, child.href) ? "page" : undefined} data-active={isPathActive(pathname, child.href)} href={child.href} key={child.id} onClick={onNavigate} prefetch={shouldPrefetchRoute(child.href)} ref={!item.href && index === 0 ? firstFlyoutItemRef : undefined}><span><SidebarIcon name={child.icon} /></span>{child.label}</Link>)}
      </nav>
    </section>
  </div>;
  return createPortal(panel, document.body);
}

function isPathActive(pathname: string, href: string) {
  return pathname === href || pathname.startsWith(`${href}/`);
}

function shouldPrefetchRoute(href: string) {
  return href === "/atendimentos";
}

function initials(name: string) {
  return name.split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("");
}

function sidebarStorageKey(userId: string) {
  return `hp-sul-sidebar:${userId}`;
}
