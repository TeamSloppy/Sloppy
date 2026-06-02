export function resolveLinkedAgentPet(actorId, actors, agentDirectory) {
  const id = String(actorId || "").trim();
  if (!id) return null;

  const actor = (Array.isArray(actors) ? actors : []).find((item) => item?.id === id);
  const linkedAgentId = String(actor?.linkedAgentId || "").trim();
  if (!linkedAgentId) return null;

  const agent = agentDirectory?.[linkedAgentId];
  const pet = agent?.pet;
  if (!pet?.parts) return null;

  return {
    pet,
    parts: pet.parts,
    genomeHex: pet.genomeHex,
    label: actor?.displayName || id
  };
}
