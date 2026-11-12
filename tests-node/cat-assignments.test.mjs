import test from 'node:test';
import assert from 'node:assert/strict';
import { CatAssignments } from '../lib/cat-assignments.mjs';
const cats = Array.from({ length: 12 }, (_, i) => ({ directory: `/cats/${i}` }));
const session = key => ({ key, activity: 'idle' });

test('uses every cat before any duplicate, then balances unavoidable reuse', () => {
  const allocator = new CatAssignments(cats, { random: () => 0.7 });
  const initial = allocator.reconcile(Array.from({ length: 12 }, (_, i) => session(String(i))), 0);
  assert.equal(new Set(initial.map(s => s.pack)).size, 12);
  const more = allocator.reconcile(Array.from({ length: 25 }, (_, i) => session(String(i))), 100);
  assert.deepEqual(more.slice(0, 12).map(s => s.pack), initial.map(s => s.pack));
  const counts = cats.map(cat => more.filter(s => s.pack === cat.directory).length);
  assert.equal(Math.max(...counts) - Math.min(...counts), 1);
});

test('session identity survives polling, reordering, activity changes and brief disappearance', () => {
  const allocator = new CatAssignments(cats, { random: () => 0 });
  const first = allocator.reconcile([session('a'), session('b')], 0);
  const second = allocator.reconcile([{ key: 'b', activity: 'working' }, session('a')], 1000);
  assert.equal(second[0].pack, first[1].pack); assert.equal(second[1].pack, first[0].pack);
  allocator.reconcile([session('b')], 2000);
  const returned = allocator.reconcile([session('a'), session('b')], 3000);
  assert.equal(returned[0].pack, first[0].pack);
});

test('reserves cats during goodbye and releases them afterward without changing survivors', () => {
  const allocator = new CatAssignments(cats.slice(0, 3), { random: () => 0 });
  const initial = allocator.reconcile([session('a'), session('b')], 0);
  allocator.reconcile([session('b')], 1000);
  const during = allocator.reconcile([session('b'), session('c')], 2000);
  assert.notEqual(during[1].pack, initial[0].pack);
  const after = allocator.reconcile([session('b'), session('c'), session('d')], 5000);
  assert.equal(after[0].pack, initial[1].pack);
  assert.equal(after[2].pack, initial[0].pack);
  allocator.reconcile([], 6000); allocator.reconcile([], 10000);
  assert.equal(allocator.assignments.size, 0);
});

test('random choice samples the available set, and an empty library fails clearly', () => {
  const first = new CatAssignments(cats, { random: () => 0 });
  const last = new CatAssignments(cats, { random: () => 1 });
  assert.notEqual(first.reconcile([session('a')])[0].pack, last.reconcile([session('a')])[0].pack);
  assert.throws(() => new CatAssignments([]), /No cat packs/);
});

test('disabled cats are replaced without disturbing enabled assignments; all disabled hides pets', () => {
  const allocator = new CatAssignments(cats, { random: () => 0 });
  const sessions = [session('a'), session('b')];
  const initial = allocator.reconcile(sessions, 0);
  allocator.setCats(cats.slice(1));
  const changed = allocator.reconcile(sessions, 1);
  assert.notEqual(changed[0].pack, initial[0].pack);
  assert.equal(changed[1].pack, initial[1].pack);
  allocator.setCats([]);
  assert.deepEqual(allocator.reconcile(sessions, 2), []);
  allocator.setCats(cats.slice(0, 1));
  assert.deepEqual(allocator.reconcile(sessions, 3).map(s => s.pack), [cats[0].directory, cats[0].directory]);
});
