export function positionName(
  profile: { position_id: number | null },
  positions: Array<{ id: number; name: string }>,
) {
  return positions.find((position) => position.id === profile.position_id)?.name ?? "Cargo não definido";
}

export function positionLevel(
  profile: { position_id: number | null },
  positions: Array<{ id: number; level: number | null }>,
) {
  return positions.find((position) => position.id === profile.position_id)?.level ?? null;
}
