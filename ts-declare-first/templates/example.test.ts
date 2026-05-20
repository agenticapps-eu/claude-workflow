/**
 * Phase 2 example — failing contract tests against the declared
 * surface.
 *
 * Spec §13 §Phase 2:
 *   - import + exercise declared symbols
 *   - ≥1 test per declared symbol
 *   - cover happy-path, error-path, edge-case
 *   - MUST be observable as failing in the expected way at this
 *     commit (declarations exist, implementations do not)
 *   - capture failing-test output as §06 evidence
 *
 * At Phase 2 the import `from './bounded-queue'` resolves via one
 * of:
 *   (a) tsconfig.json paths alias './bounded-queue' →
 *       './bounded-queue.declare'
 *   (b) stub `bounded-queue.ts` that re-exports from the declare
 *       file (replaced by real impl at Phase 3)
 *   (c) direct `from './bounded-queue.declare'` import (changed
 *       to './bounded-queue' at Phase 3)
 *
 * The choice is the host's per spec §13 — this template assumes
 * (a) or (b). For (c), change the import path below.
 *
 * Framework-agnostic: this example uses `vitest`-shape; adapt to
 * jest / node:test / deno test / bun test per the host's test
 * framework. The §06 evidence rule cares about the
 * expected-failure shape, not the runner.
 */

import { describe, it, expect } from 'vitest';
import { BoundedQueue } from './bounded-queue';

describe('BoundedQueue (Phase 2 contract tests)', () => {
  it('reports capacity from the constructor', () => {
    const q = new BoundedQueue<number>(3);
    expect(q.capacity).toBe(3);
    expect(q.size).toBe(0);
  });

  it('preserves FIFO order on enqueue/dequeue', () => {
    const q = new BoundedQueue<string>(3);
    q.enqueue('a');
    q.enqueue('b');
    q.enqueue('c');
    expect(q.dequeue()).toBe('a');
    expect(q.dequeue()).toBe('b');
    expect(q.dequeue()).toBe('c');
  });

  it('rejects enqueue at capacity', () => {
    const q = new BoundedQueue<number>(2);
    expect(q.enqueue(1)).toBe(true);
    expect(q.enqueue(2)).toBe(true);
    expect(q.enqueue(3)).toBe(false);
    expect(q.size).toBe(2);
  });

  it('returns undefined when dequeueing empty', () => {
    const q = new BoundedQueue<number>(2);
    expect(q.dequeue()).toBeUndefined();
  });
});
