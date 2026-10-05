import { cookies } from "next/headers";
import { RECRUITMENT_NOTICE_KEY } from "../../lib/recruitment";
import { getSupabaseAdminConfig, normalizePassport } from "../../lib/supabase-server";

const PHONE_PATTERN = /^\([0-9]{3}\) [0-9]{3}-[0-9]{3}$/;
const DISCORD_PATTERN = /^[0-9]{17,20}$/;
const AVAILABILITY = new Set(["morning", "afternoon", "evening", "overnight"]);
const INTEREST_AREAS = new Set([
  "clinical_care",
  "emergency_rescue",
  "nursing",
  "health_management",
  "undecided",
]);
const EXTERNAL_CALLS = new Set(["full", "partial", "unavailable"]);

type RecruitmentPayload = {
  availability?: unknown;
  birthDay?: unknown;
  birthMonth?: unknown;
  cityPhone?: unknown;
  discordId?: unknown;
  experienceSummary?: unknown;
  externalCalls?: unknown;
  fullName?: unknown;
  interestArea?: unknown;
  motivation?: unknown;
  passport?: unknown;
  priorExperience?: unknown;
  website?: unknown;
};

export async function POST(request: Request) {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > 30_000) {
    return Response.json({ error: "A candidatura excedeu o tamanho permitido." }, { status: 413 });
  }

  const cookieStore = await cookies();
  if (cookieStore.get(RECRUITMENT_NOTICE_KEY)?.value !== "true") {
    return Response.json({ error: "Confirme as orientações antes de enviar a candidatura." }, { status: 403 });
  }

  try {
    const body = (await request.json()) as RecruitmentPayload;
    if (typeof body.website === "string" && body.website.trim()) {
      return Response.json({ protocol: "HPSM-RECEBIDO" }, { status: 201 });
    }

    const fullName = requiredText(body.fullName, 2, 100);
    const passport = normalizePassport(requiredText(body.passport, 1, 4));
    const cityPhone = requiredText(body.cityPhone, 13, 13);
    const discordId = requiredText(body.discordId, 17, 20);
    const birthDay = integerBetween(body.birthDay, 1, 31);
    const birthMonth = integerBetween(body.birthMonth, 1, 12);
    const priorExperience = body.priorExperience;
    const interestArea = requiredText(body.interestArea, 2, 40);
    const motivation = requiredText(body.motivation, 30, 1200);
    const externalCalls = requiredText(body.externalCalls, 2, 30);
    const experienceSummary = optionalText(body.experienceSummary, 1000);
    const availability = arrayOfAllowedStrings(body.availability, AVAILABILITY, 4);

    if (!PHONE_PATTERN.test(cityPhone)) throw new Error("phone");
    if (!DISCORD_PATTERN.test(discordId)) throw new Error("discord");
    if (typeof priorExperience !== "boolean") throw new Error("experience");
    if (!INTEREST_AREAS.has(interestArea)) throw new Error("interest");
    if (!EXTERNAL_CALLS.has(externalCalls)) throw new Error("calls");

    const { url, serviceRoleKey } = getSupabaseAdminConfig();
    const response = await fetch(`${url}/rest/v1/recruitment_applications?select=id`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        "content-type": "application/json",
        prefer: "return=representation",
      },
      body: JSON.stringify({
        full_name: fullName,
        passport,
        birth_day: birthDay,
        birth_month: birthMonth,
        city_phone: cityPhone,
        discord_id: discordId,
        availability,
        prior_experience: priorExperience,
        experience_summary: experienceSummary,
        interest_area: interestArea,
        motivation,
        external_calls: externalCalls,
      }),
    });

    if (response.status === 409) {
      return Response.json(
        { error: "Já existe uma candidatura registrada com este passaporte ou ID do Discord." },
        { status: 409 },
      );
    }
    if (!response.ok) throw new Error("insert");
    const rows = (await response.json()) as { id?: string }[];
    const id = rows[0]?.id;
    if (!id) throw new Error("representation");
    return Response.json({ protocol: `HPSM-${id.slice(0, 8).toUpperCase()}` }, { status: 201 });
  } catch {
    return Response.json(
      { error: "Revise os campos obrigatórios e tente novamente." },
      { status: 400 },
    );
  }
}

function requiredText(value: unknown, min: number, max: number) {
  if (typeof value !== "string") throw new Error("text");
  const result = value.trim();
  if (result.length < min || result.length > max) throw new Error("text");
  return result;
}

function optionalText(value: unknown, max: number) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") throw new Error("text");
  const result = value.trim();
  if (result.length > max) throw new Error("text");
  return result || null;
}

function integerBetween(value: unknown, min: number, max: number) {
  const result = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(result) || result < min || result > max) throw new Error("number");
  return result;
}

function arrayOfAllowedStrings(value: unknown, allowed: Set<string>, max: number) {
  if (!Array.isArray(value) || value.length < 1 || value.length > max) throw new Error("array");
  const result = [...new Set(value)];
  if (result.some((item) => typeof item !== "string" || !allowed.has(item))) throw new Error("array");
  return result;
}
