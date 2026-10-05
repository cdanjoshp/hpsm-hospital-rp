import type { Metadata } from "next";
import "./globals.css";
import "./brand.css";
import { RpDisclaimer } from "./components/rp-disclaimer";
import { PersistentAppShell } from "./components/persistent-app-shell";
import { DEPLOYMENT_RECOVERY_BOOTSTRAP_SCRIPT } from "./lib/deployment-recovery";
import { getSessionBootstrap } from "./lib/session";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.PUBLIC_SITE_URL || "http://localhost:3000"),
  title: "HPSM — Sistema Interno",
  description:
    "Portal reservado para gestão clínica e administrativa do Hospital Santa Marcelina.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
  openGraph: {
    title: "HPSM — Sistema Interno",
    description: "Gestão hospitalar segura, organizada e auditável.",
    type: "website",
    images: [{ url: "/og.png", width: 1731, height: 909, alt: "HPSM — Hospital Santa Marcelina" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "HPSM — Sistema Interno",
    description: "Gestão hospitalar segura, organizada e auditável.",
    images: ["/og.png"],
  },
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const context = await getSessionBootstrap();
  const dashboardGreeting = getDashboardGreeting();
  return (
    <html lang="pt-BR">
      <body>
        <script dangerouslySetInnerHTML={{ __html: DEPLOYMENT_RECOVERY_BOOTSTRAP_SCRIPT }} />
        {context ? (
          <PersistentAppShell key={context.profile.user_id} dashboardGreeting={dashboardGreeting} permissionCodes={context.permissionCodes} positionDisplayName={context.positionDisplayName} profile={context.profile}>
            {children}
          </PersistentAppShell>
        ) : children}
        <RpDisclaimer />
      </body>
    </html>
  );
}

function getDashboardGreeting() {
  const hour = Number(new Intl.DateTimeFormat("pt-BR", {
    hour: "2-digit",
    hourCycle: "h23",
    timeZone: "America/Sao_Paulo",
  }).format(new Date()));
  return hour < 12 ? "Bom dia" : hour < 18 ? "Boa tarde" : "Boa noite";
}
