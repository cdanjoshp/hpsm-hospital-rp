"use client";

import { HpsmButton } from "./hpsm-button";
import { useModalFocus } from "./use-modal-focus";

export function DocumentImageViewer({ downloadUrl, imageUrl, onClose, title }: { downloadUrl?: string | null; imageUrl: string; onClose: () => void; title: string }) {
  const dialogRef = useModalFocus(onClose);
  return <div className="document-image-viewer-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <section aria-label={title} aria-modal="true" className="document-image-viewer" ref={dialogRef} role="dialog" tabIndex={-1}>
      <header><div><span>Documento institucional</span><h2>{title}</h2></div><button aria-label="Fechar visualização" onClick={onClose} type="button">×</button></header>
      <div className="document-image-viewer-stage">{/* A imagem autenticada/dinâmica não deve passar pelo otimizador externo do Next. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img alt={title} src={imageUrl} />
      </div>
      <footer>{downloadUrl ? <a className="hpsm-button hpsm-button-primary" href={downloadUrl}>Baixar imagem</a> : null}<HpsmButton onClick={onClose} type="button" variant="ghost">Fechar</HpsmButton></footer>
    </section>
  </div>;
}
