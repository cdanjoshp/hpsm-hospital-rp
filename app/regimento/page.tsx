import type { Metadata } from "next";
import { RegimentoPage } from "../components/regimento-page";

export const metadata: Metadata = {
  title: "Regimento Interno | Hospital Santa Marcelina",
  description: "Regimento Interno e Normas de Boas Práticas do Hospital Santa Marcelina — Cidade dos Anjos.",
};

export default function Page() {
  return <RegimentoPage />;
}
