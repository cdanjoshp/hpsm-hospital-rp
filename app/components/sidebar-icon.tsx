import type { SidebarIconName } from "../lib/sidebar-navigation";

export function SidebarIcon({ name }: { name: SidebarIconName }) {
  const content = iconContent(name);
  return (
    <svg aria-hidden="true" fill="none" focusable="false" viewBox="0 0 24 24">
      <g stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8">
        {content}
      </g>
    </svg>
  );
}

function iconContent(name: SidebarIconName) {
  switch (name) {
    case "academy":
      return <><path d="M3.5 5.5c3.1-1.1 5.7-.6 8.5 1.2 2.8-1.8 5.4-2.3 8.5-1.2v13c-3.1-1.1-5.7-.6-8.5 1.2-2.8-1.8-5.4-2.3-8.5-1.2Z" /><path d="M12 6.7v13" /></>;
    case "academy-management":
      return <><path d="M4 6.5 12 3l8 3.5-8 3.5Z" /><path d="M7 9v5.5c2.8 2.1 7.2 2.1 10 0V9M20 6.5v8" /><circle cx="20" cy="16" r="1" /></>;
    case "dashboard":
      return <><path d="m3 10.5 9-7.5 9 7.5" /><path d="M5.5 9.5V21h13V9.5M9 21v-7h6v7" /></>;
    case "patients":
      return <><circle cx="9" cy="8" r="3" /><path d="M3.5 20c.4-4 2.2-6 5.5-6s5.1 2 5.5 6M16 7.5a2.5 2.5 0 0 1 0 5M16 15c2.8.2 4.3 1.9 4.5 5" /></>;
    case "attendances":
      return <><rect x="4" y="4" width="16" height="16" rx="4" /><path d="M12 8v8M8 12h8" /></>;
    case "consultations":
      return <><rect x="3.5" y="5" width="17" height="15.5" rx="3" /><path d="M7.5 3v4M16.5 3v4M3.5 9.5h17M8 14h3M8 17h6" /></>;
    case "assist":
      return <><path d="M12 2.8 14 8l5.2 2-5.2 2-2 5.2-2-5.2-5.2-2L10 8Z" /><path d="m19 16 .7 1.8 1.8.7-1.8.7L19 21l-.7-1.8-1.8-.7 1.8-.7Z" /></>;
    case "exams":
      return <><path d="M9 3h6M10 3v5l-5.4 9.1A2.6 2.6 0 0 0 6.8 21h10.4a2.6 2.6 0 0 0 2.2-3.9L14 8V3" /><path d="M7.2 16h9.6" /></>;
    case "casts":
      return <><path d="m7.1 18.3-1.4-1.4a3.2 3.2 0 0 1 0-4.6l6.6-6.6a3.2 3.2 0 0 1 4.6 0l1.4 1.4a3.2 3.2 0 0 1 0 4.6l-6.6 6.6a3.2 3.2 0 0 1-4.6 0Z" /><path d="m9 9 6 6M9.2 13.8h.1M13.8 9.2h.1" /></>;
    case "hospitalizations":
      return <><path d="M3 20V8h18v12M3 15h18M7 12h3M6 8V5h4a3 3 0 0 1 3 3" /><path d="M7 20v-5M17 20v-5" /></>;
    case "certificates":
      return <><path d="M6 3.5h9l3 3V21H6Z" /><path d="M15 3.5V7h3M9 11h6M9 15h6M9 18h3" /></>;
    case "my-hr":
    case "rh":
      return <><circle cx="12" cy="12" r="8.5" /><path d="M12 7v5l3.5 2" /></>;
    case "catalog":
      return <><circle cx="8" cy="8" r="2" /><circle cx="16" cy="16" r="2" /><path d="m7 18 10-12" /></>;
    case "administrative":
      return <><rect x="5" y="4.5" width="14" height="16" rx="2.5" /><path d="M9 4.5V3h6v1.5M9 9h6M9 13h6M9 17h4" /></>;
    case "audit":
      return <><path d="M5 5h9M5 10h7M5 15h5" /><circle cx="16" cy="16" r="3.5" /><path d="m18.5 18.5 2 2" /></>;
    case "communications":
      return <><path d="M6.5 9a5.5 5.5 0 0 1 11 0c0 6 2.5 6 2.5 7.5H4C4 15 6.5 15 6.5 9" /><path d="M10 20h4" /></>;
    case "pending":
      return <><circle cx="12" cy="12" r="9" /><path d="M12 7.5v5.5M12 16.5h.01" /></>;
    case "career":
      return <><path d="M4 18 10 12l4 3 6-8" /><path d="M15 7h5v5" /></>;
    case "recruitment":
      return <><circle cx="9" cy="8" r="3" /><path d="M3.5 20c.4-4 2.2-6 5.5-6 2.1 0 3.6.8 4.5 2.4M18 13v7M14.5 16.5h7" /></>;
    case "partnerships":
      return <><path d="M8.5 8.5 6 6a3.5 3.5 0 0 0-5 5l3 3a3.5 3.5 0 0 0 5 0l1-1" /><path d="m15.5 15.5 2.5 2.5a3.5 3.5 0 0 0 5-5l-3-3a3.5 3.5 0 0 0-5 0l-1 1M8 16l8-8" /></>;
    case "team":
      return <><circle cx="8" cy="8" r="3" /><circle cx="17" cy="9" r="2.5" /><path d="M2.8 20c.4-4 2.1-6 5.2-6s4.8 2 5.2 6M14 15c3.9-.5 6.3 1.2 6.7 5" /></>;
    case "profiles":
      return <><rect x="3" y="5" width="18" height="14" rx="2.5" /><circle cx="8" cy="11" r="2.2" /><path d="M5.5 16c.3-1.7 1.1-2.5 2.5-2.5s2.2.8 2.5 2.5M14 10h4M14 14h4" /></>;
    case "reports":
      return <><path d="M5 20V10M12 20V4M19 20v-7M3 20h18" /></>;
    case "records":
      return <><rect x="4" y="3" width="16" height="18" rx="2" /><path d="M8 8h8M8 12h8M8 16h5" /></>;
  }
}
