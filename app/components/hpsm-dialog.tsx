"use client";

import type { ReactNode } from "react";
import { useModalFocus } from "./use-modal-focus";
import { HpsmButton, type HpsmButtonVariant } from "./hpsm-button";

export function HpsmDialog({ cancelLabel = "Voltar", confirmLabel, confirmVariant = "primary", description, loading = false, onClose, onConfirm, title, children }: {
  cancelLabel?: string;
  children?: ReactNode;
  confirmLabel?: string;
  confirmVariant?: HpsmButtonVariant;
  description: string;
  loading?: boolean;
  onClose: () => void;
  onConfirm?: () => void;
  title: string;
}) {
  const dialogRef = useModalFocus(onClose);
  return <div className="hpsm-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target && !loading) onClose(); }}>
    <section ref={dialogRef} className="hpsm-dialog" role="dialog" aria-modal="true" aria-labelledby="hpsm-dialog-title" aria-describedby="hpsm-dialog-description" tabIndex={-1}>
      <header><span aria-hidden="true">+</span><div><p>Confirmação clínica</p><h2 id="hpsm-dialog-title">{title}</h2></div></header>
      <p id="hpsm-dialog-description">{description}</p>
      {children}
      <footer>
        <HpsmButton type="button" variant="ghost" disabled={loading} onClick={onClose}>{cancelLabel}</HpsmButton>
        {confirmLabel && onConfirm ? <HpsmButton type="button" variant={confirmVariant} loading={loading} onClick={onConfirm}>{confirmLabel}</HpsmButton> : null}
      </footer>
    </section>
  </div>;
}
