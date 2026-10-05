export type DocumentMediaType = "CONSULTATION_RECORD" | "EXAM" | "MEDICAL_CERTIFICATE" | "PRESCRIPTION";
export type DocumentPublicationStatus = "FAILED" | "PENDING" | "PUBLISHED" | "PUBLISHING";

export type DocumentImagePublication = {
  cdn_url: string | null;
  created_at: string;
  document_id: number;
  document_type: DocumentMediaType;
  external_asset_id: string | null;
  id: string;
  last_error: string | null;
  mime_type: "image/png";
  provider: "fivemanage";
  publication_status: DocumentPublicationStatus;
  render_version: string;
  updated_at: string;
  uploaded_at: string | null;
};

export type DocumentPublicationClientState = {
  publication: DocumentImagePublication | null;
  publicationError: string | null;
  publicationStatus: DocumentPublicationStatus | null;
};

