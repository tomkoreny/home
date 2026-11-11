// OMP for herdr-chat. OMP has no fixed input box the chat could mirror a
// draft into, so the reply box keeps its own draft (`mirror`, `box`).
export default {
  id: "omp",
  label: "omp",
  images: "path",
  mirror: false,
  prompt: {},
  box: null,
  skills: { triggers: ["/"], invoke: "/skill:", user: ["~/.omp/agent/skills", "~/.agents/skills"], project: [".omp/skills", ".agents/skills"], skip: [] },
  reader: "omp",
};
