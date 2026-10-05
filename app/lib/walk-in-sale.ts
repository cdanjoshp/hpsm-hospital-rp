const WALK_IN_CATEGORIES = new Set(["insumos", "medicamentos", "deslocamento"]);
const WALK_IN_SERVICE_CODES = new Set(["tratamento", "desloc_norte", "desloc_sul"]);

export function isWalkInService(service: { category: string; code: string }) {
  const category = service.category.trim().toLocaleLowerCase("pt-BR");
  const code = service.code.trim().toLocaleLowerCase("pt-BR");
  return WALK_IN_CATEGORIES.has(category) || WALK_IN_SERVICE_CODES.has(code);
}
