import { useId } from "react";
import { HPSM_COMPASS_FACETS } from "../lib/hpsm-brand";

type HpsmLogoProps = {
  className?: string;
  compact?: boolean;
  markOnly?: boolean;
};

export function HpsmLogo({ className = "", compact = false, markOnly = false }: HpsmLogoProps) {
  if (markOnly) {
    return <HpsmCompass className={className} />;
  }

  return (
    <span className={`hpsm-logo${compact ? " hpsm-logo-compact" : ""} ${className}`.trim()}>
      <HpsmCompass />
      <span className="hpsm-wordmark">
        <strong>HPSM</strong>
        <span>Hospital Santa Marcelina</span>
      </span>
    </span>
  );
}

export function HpsmCompass({ className = "" }: { className?: string }) {
  const gradientId = `hpsm-${useId().replace(/[^A-Za-z0-9_-]/g, "")}`;
  return (
    <svg
      aria-hidden="true"
      className={`hpsm-compass ${className}`.trim()}
      focusable="false"
      viewBox="0 0 120 120"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <linearGradient id={`${gradientId}-light`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#b7e9ff" />
          <stop offset="0.42" stopColor="#2b9ae7" />
          <stop offset="1" stopColor="#07599e" />
        </linearGradient>
        <linearGradient id={`${gradientId}-blue`} x1="0" y1="0" x2="0.85" y2="1">
          <stop offset="0" stopColor="#5abaff" />
          <stop offset="0.48" stopColor="#0878d1" />
          <stop offset="1" stopColor="#07509a" />
        </linearGradient>
        <linearGradient id={`${gradientId}-navy`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#2169a8" />
          <stop offset="0.5" stopColor="#0b3972" />
          <stop offset="1" stopColor="#071e3e" />
        </linearGradient>
        <filter id={`${gradientId}-shadow`} x="-25%" y="-25%" width="150%" height="160%">
          <feDropShadow dx="0" dy="4" floodColor="#061b36" floodOpacity="0.24" stdDeviation="3" />
        </filter>
      </defs>
      <g filter={`url(#${gradientId}-shadow)`} stroke="#8bd2ff" strokeOpacity="0.18" strokeWidth="0.45" strokeLinejoin="round">
        {HPSM_COMPASS_FACETS.map(({ d, tone }) => <path key={d} d={d} fill={`url(#${gradientId}-${tone})`} />)}
      </g>
    </svg>
  );
}
