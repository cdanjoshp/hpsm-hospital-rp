"use client";

import Link from "next/link";
import type { ButtonHTMLAttributes, ReactNode } from "react";

export type HpsmButtonVariant = "primary" | "secondary" | "ghost" | "destructive";

export function hpsmButtonClass(variant: HpsmButtonVariant = "secondary", className = "") {
  return `hpsm-button hpsm-button-${variant}${className ? ` ${className}` : ""}`;
}

export function HpsmButton({ children, className = "", loading = false, variant = "secondary", ...props }: ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode;
  loading?: boolean;
  variant?: HpsmButtonVariant;
}) {
  return <button {...props} className={hpsmButtonClass(variant, className)} disabled={props.disabled || loading} aria-busy={loading || undefined}>
    {loading ? <span className="hpsm-button-spinner" aria-hidden="true" /> : null}
    <span>{children}</span>
  </button>;
}

export function HpsmButtonLink({ children, className = "", href, target, variant = "secondary" }: {
  children: ReactNode;
  className?: string;
  href: string;
  target?: string;
  variant?: HpsmButtonVariant;
}) {
  if (href.startsWith("/api/")) return <a className={hpsmButtonClass(variant, className)} href={href} target={target} rel={target === "_blank" ? "noopener noreferrer" : undefined}>{children}</a>;
  return <Link className={hpsmButtonClass(variant, className)} href={href} target={target}>{children}</Link>;
}
