import React from "react";
import { AgentPetSprite } from "./AgentPetSprite";

const STAT_ITEMS = [
  { key: "wisdom", label: "WISDOM" },
  { key: "debugging", label: "Debugging" },
  { key: "patience", label: "PATIENCE" },
  { key: "snark", label: "SNARK" },
  { key: "chaos", label: "CHAOS" }
];

function formatPart(id: string | undefined) {
  if (!id) return "unknown";
  return id.replace(/^(head|body|legs|face|acc)-/, "").replace(/-/g, " ");
}

export function AgentPetCard({ pet }: { pet?: any }) {
  if (!pet) {
    return null;
  }

  const currentStats = pet.currentStats || pet.baseStats || {};
  const baseStats = pet.baseStats || {};
  const visual = pet.visual || null;
  const evolution = pet.evolution || {};
  const totalXp = Number(evolution.totalXp || 0);
  const nextStageXp = Number(evolution.nextStageXp || 0);
  const progress = nextStageXp > 0 ? Math.max(0, Math.min((totalXp / nextStageXp) * 100, 100)) : 100;

  return (
    <section className="dashboard-section agent-pet-section">
      <div className="dashboard-section-header">
        <h3>Sloppie</h3>
        <span className={`badge badge-pet badge-pet-${String(pet.rarity || "common").toLowerCase()}`}>{pet.rarity || "common"}</span>
      </div>

      <div className="agent-pet-card">
        <div className="agent-pet-stage">
          <AgentPetSprite pet={pet} parts={pet.parts} genomeHex={pet.genomeHex} />
          <div className="agent-pet-stage-meta">
            <span className="agent-pet-id">{visual?.displayName || pet.petId || "pet-unknown"}</span>
            <span className="agent-pet-genome">Genome {pet.genomeHex || "0000000000000000"}</span>
            {visual && (
              <>
                <span className="agent-pet-genome">Stage {visual.currentStage}/{visual.stageCount}</span>
                <span className="agent-pet-terminal-face">{visual.terminalFaceSet?.idle || "(o_o)"}</span>
              </>
            )}
          </div>
        </div>

        <div className="agent-pet-panel">
          {visual && (
            <div className="agent-pet-evolution">
              <div className="agent-pet-evolution-head">
                <span>{totalXp} XP</span>
                <span>{evolution.isMaxStage ? "Max stage" : `Next ${nextStageXp} XP`}</span>
              </div>
              <div className="agent-pet-stat-meter agent-pet-evolution-meter">
                <div className="agent-pet-stat-fill" style={{ width: `${progress}%` }} />
              </div>
            </div>
          )}

          <div className="agent-pet-parts">
            <span>Head: {formatPart(pet.parts?.headId)}</span>
            <span>Body: {formatPart(pet.parts?.bodyId)}</span>
            <span>Legs: {formatPart(pet.parts?.legsId)}</span>
            {pet.parts?.faceId && pet.parts.faceId !== "face-default" && (
              <span>Face: {formatPart(pet.parts.faceId)}</span>
            )}
            {pet.parts?.accessoryId && pet.parts.accessoryId !== "acc-none" && (
              <span>Acc: {formatPart(pet.parts.accessoryId)}</span>
            )}
          </div>

          <div className="agent-pet-stats">
            {STAT_ITEMS.map((item) => {
              const currentValue = Number(currentStats[item.key] || 0);
              const baseValue = Number(baseStats[item.key] || 0);
              return (
                <div key={item.key} className="agent-pet-stat-row">
                  <span className="agent-pet-stat-label">{item.label}</span>
                  <div className="agent-pet-stat-meter">
                    <div className="agent-pet-stat-fill" style={{ width: `${Math.max(0, Math.min(currentValue, 100))}%` }} />
                    <div className="agent-pet-stat-base" style={{ width: `${Math.max(0, Math.min(baseValue, 100))}%` }} />
                  </div>
                  <span className="agent-pet-stat-value">{currentValue}</span>
                </div>
              );
            })}
          </div>

          <p className="agent-pet-note">
            Stats aggregate across direct chats, linked channels, heartbeats, and automated runs.
          </p>
        </div>
      </div>
    </section>
  );
}
