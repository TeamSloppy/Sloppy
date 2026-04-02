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
  return id.replace(/^(head|body|legs)-/, "").replace(/-/g, " ");
}

export function AgentPetCard({ pet }: { pet?: any }) {
  if (!pet) {
    return null;
  }

  const currentStats = pet.currentStats || pet.baseStats || {};
  const baseStats = pet.baseStats || {};

  return (
    <section className="dashboard-section agent-pet-section">
      <div className="dashboard-section-header">
        <h3>Tamagotchi</h3>
        <span className={`badge badge-pet badge-pet-${String(pet.rarity || "common").toLowerCase()}`}>{pet.rarity || "common"}</span>
      </div>

      <div className="agent-pet-card">
        <div className="agent-pet-stage">
          <AgentPetSprite parts={pet.parts} />
          <div className="agent-pet-stage-meta">
            <span className="agent-pet-id">{pet.petId || "pet-unknown"}</span>
            <span className="agent-pet-genome">Genome {pet.genomeHex || "0000000000000000"}</span>
          </div>
        </div>

        <div className="agent-pet-panel">
          <div className="agent-pet-parts">
            <span>Head: {formatPart(pet.parts?.headId)}</span>
            <span>Body: {formatPart(pet.parts?.bodyId)}</span>
            <span>Legs: {formatPart(pet.parts?.legsId)}</span>
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
