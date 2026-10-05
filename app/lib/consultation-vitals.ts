export type VitalClassification = "Baixo" | "Normal" | "Elevado" | "Crítico";
export type VitalCode = "blood_pressure" | "temperature" | "heart_rate" | "oxygen_saturation";
export type VitalRangeConfiguration = Record<string, number | Record<string, Record<string, number>>>;
export type ConsultationVitalRanges = Partial<Record<VitalCode, VitalRangeConfiguration>>;

function numeric(configuration: VitalRangeConfiguration | undefined, name: string, fallback: number) {
  const value = configuration?.[name];
  return typeof value === "number" ? value : fallback;
}

export function classifyBloodPressure(systolic: number, diastolic: number, ranges?: ConsultationVitalRanges): VitalClassification {
  const configuration = ranges?.blood_pressure;
  if (systolic >= numeric(configuration, "criticalSystolicMin", 180) || diastolic >= numeric(configuration, "criticalDiastolicMin", 120)) return "Crítico";
  if (systolic <= numeric(configuration, "lowSystolicMax", 89) || diastolic <= numeric(configuration, "lowDiastolicMax", 59)) return "Baixo";
  if (systolic >= numeric(configuration, "highSystolicMin", 130) || diastolic >= numeric(configuration, "highDiastolicMin", 85)) return "Elevado";
  return "Normal";
}

export function classifyTemperature(value: number, ranges?: ConsultationVitalRanges): VitalClassification {
  const configuration = ranges?.temperature;
  if (value >= numeric(configuration, "criticalMin", 39.5)) return "Crítico";
  if (value <= numeric(configuration, "lowMax", 35.4)) return "Baixo";
  if (value >= numeric(configuration, "highMin", 37.5)) return "Elevado";
  return "Normal";
}

export function classifyHeartRate(value: number, ranges?: ConsultationVitalRanges): VitalClassification {
  const configuration = ranges?.heart_rate;
  if (value <= numeric(configuration, "criticalLowMax", 39) || value >= numeric(configuration, "criticalHighMin", 150)) return "Crítico";
  if (value <= numeric(configuration, "lowMax", 59)) return "Baixo";
  if (value >= numeric(configuration, "highMin", 101)) return "Elevado";
  return "Normal";
}

export function classifyOxygenSaturation(value: number, ranges?: ConsultationVitalRanges): VitalClassification {
  const configuration = ranges?.oxygen_saturation;
  if (value <= numeric(configuration, "criticalMax", 89)) return "Crítico";
  if (value <= numeric(configuration, "lowMax", 94)) return "Baixo";
  if (value >= numeric(configuration, "elevatedMin", 98)) return "Elevado";
  return "Normal";
}

function randomInteger(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function generationRange(ranges: ConsultationVitalRanges, code: VitalCode, classification: VitalClassification) {
  const generation = ranges[code]?.generation;
  const range = generation && typeof generation === "object" && !Array.isArray(generation) ? generation[classification] : undefined;
  return range && typeof range === "object" ? range : null;
}

export function generateVitalForClassification(code: VitalCode, classification: VitalClassification, ranges: ConsultationVitalRanges): { systolic: number; diastolic: number } | { value: number } | null {
  const range = generationRange(ranges, code, classification);
  if (!range) return null;
  if (code === "blood_pressure") {
    if (![range.systolicMin, range.systolicMax, range.diastolicMin, range.diastolicMax].every((value) => typeof value === "number")) return null;
    return {
      systolic: randomInteger(range.systolicMin!, range.systolicMax!),
      diastolic: randomInteger(range.diastolicMin!, range.diastolicMax!),
    };
  }
  if (typeof range.min !== "number" || typeof range.max !== "number") return null;
  const value = code === "temperature"
    ? Number((range.min + Math.random() * (range.max - range.min)).toFixed(1))
    : randomInteger(range.min, range.max);
  return { value };
}
