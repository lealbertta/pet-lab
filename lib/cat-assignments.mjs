// Keep a session's appearance stable; reserve departing cats through their goodbye.
export class CatAssignments {
  constructor(cats, { random = Math.random, retirementMs = 4000 } = {}) {
    if (!cats.length) throw new Error('No cat packs available for -multicats');
    this.cats = cats;
    this.random = random;
    this.retirementMs = retirementMs;
    this.assignments = new Map();
  }

  setCats(cats) {
    this.cats = cats;
    const allowed = new Set(cats.map(cat => cat.directory));
    for (const [key, { cat }] of this.assignments) {
      if (!allowed.has(cat.directory)) this.assignments.delete(key);
    }
  }

  reconcile(sessions, now = Date.now()) {
    if (!this.cats.length) return [];
    const active = new Set(sessions.map(session => session.key));
    for (const [key, assignment] of this.assignments) {
      if (active.has(key)) delete assignment.departedAt;
      else {
        assignment.departedAt ??= now;
        if (now - assignment.departedAt >= this.retirementMs) this.assignments.delete(key);
      }
    }
    for (const key of active) {
      if (this.assignments.has(key)) continue;
      const usage = new Map(this.cats.map(cat => [cat.directory, 0]));
      for (const { cat } of this.assignments.values()) usage.set(cat.directory, usage.get(cat.directory) + 1);
      const minimum = Math.min(...usage.values());
      const available = this.cats.filter(cat => usage.get(cat.directory) === minimum);
      const sample = this.random();
      const index = Math.floor(Math.min(Math.max(Number.isFinite(sample) ? sample : 0, 0), 0.999999999) * available.length);
      this.assignments.set(key, { cat: available[index] });
    }
    return sessions.map(session => ({ ...session, pack: this.assignments.get(session.key).cat.directory }));
  }
}
