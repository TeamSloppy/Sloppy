import assert from "node:assert/strict";
import test from "node:test";

import { resolveLinkedAgentPet } from "../src/views/Projects/commentAvatars.js";

test("project task comments resolve a linked actor to the agent pet avatar", () => {
  const pet = {
    parts: { body: "mint" },
    genomeHex: "abc123"
  };

  const avatar = resolveLinkedAgentPet(
    "actor-anton",
    [
      { id: "actor-anton", displayName: "Антон", linkedAgentId: "agent-anton" },
      { id: "actor-user", displayName: "User" }
    ],
    {
      "agent-anton": {
        displayName: "Agent: Антон",
        pet
      }
    }
  );

  assert.deepEqual(avatar, {
    pet,
    parts: pet.parts,
    genomeHex: pet.genomeHex,
    label: "Антон"
  });
});

test("project task comments keep icon fallback when actor has no linked pet", () => {
  assert.equal(
    resolveLinkedAgentPet(
      "actor-user",
      [{ id: "actor-user", displayName: "User" }],
      {}
    ),
    null
  );
});
