/**
 * Phase 3 example — implementation matching the declared surface.
 *
 * Spec §13 §Phase 3:
 *   - exported signatures match the declared signatures exactly
 *   - widening / narrowing / renaming requires an ADR
 *   - Phase-2 tests now pass
 *   - preservation of the declare file per §13's two options:
 *     (1) keep `<name>.declare.ts` as the public type surface and
 *         re-export from this impl; impl file is non-public
 *     (2) delete `<name>.declare.ts` once tsc emits the .d.ts
 *         from this file; record the transition in the commit
 *
 * Non-normative — the bounded-queue example uses an Array<T> with
 * shift() for FIFO. A real impl might prefer a linked list for
 * O(1) dequeue at large sizes.
 */

export class BoundedQueue<T> {
  readonly capacity: number;
  private items: T[] = [];

  constructor(capacity: number) {
    this.capacity = capacity;
  }

  get size(): number {
    return this.items.length;
  }

  enqueue(item: T): boolean {
    if (this.items.length >= this.capacity) return false;
    this.items.push(item);
    return true;
  }

  dequeue(): T | undefined {
    return this.items.shift();
  }
}
