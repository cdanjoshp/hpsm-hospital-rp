"use client";

import { useState } from "react";

type CatalogImageProps = {
  alt?: string;
  deferUntilResolved?: boolean;
  icon: string;
  imagePath: string | null;
  imageUrl?: string | null;
  serviceId: number;
  size?: "card" | "compact" | "small" | "preview";
};

export function CatalogImage({ alt = "", deferUntilResolved = false, icon, imagePath, imageUrl, serviceId, size = "small" }: CatalogImageProps) {
  const [failure, setFailure] = useState<{ path: string; source: string } | null>(null);
  const fallbackUrl = `/api/services/image?id=${serviceId}`;
  const failedSource = failure?.path === imagePath ? failure.source : null;
  const source = imageUrl && failedSource !== imageUrl ? imageUrl : fallbackUrl;
  const imagePending = deferUntilResolved && Boolean(imagePath) && imageUrl === undefined;
  const hasImage = Boolean(imagePath) && !imagePending && failedSource !== fallbackUrl;

  return (
    <span className={`catalog-image catalog-image-${size}`} data-fallback={!hasImage}>
      {hasImage ? (
        <img
          alt={alt}
          decoding="async"
          loading={size === "preview" ? "eager" : "lazy"}
          onError={() => imagePath && setFailure({ path: imagePath, source })}
          src={source}
        />
      ) : (
        <span aria-hidden="true">{icon}</span>
      )}
    </span>
  );
}
