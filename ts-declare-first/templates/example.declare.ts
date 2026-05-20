/**
 * Phase 1 example — declaration surface only.
 *
 * Spec §13 §Phase 1:
 *   - declare-only file; no function bodies, no expression
 *     initialisers, no other executable code
 *   - type-check-clean against tsc --noEmit
 *   - colocate with eventual impl per host convention
 *     (here: bounded-queue.declare.ts alongside bounded-queue.ts)
 *
 * Non-normative — adapt to the module you're authoring.
 *
 * Companion files:
 *   - example.test.ts       (Phase 2 — failing tests)
 *   - example.impl.ts       (Phase 3 — implementation)
 */

/**
 * A FIFO queue with a fixed maximum capacity. Enqueue is rejected
 * when the queue is full; dequeue returns undefined when empty.
 *
 * @throws never — bounded behaviour is encoded in return values,
 *         not exceptions.
 */
export declare class BoundedQueue<T> {
  constructor(capacity: number);
  readonly capacity: number;
  readonly size: number;
  /** Returns true if the item was added; false if the queue is full. */
  enqueue(item: T): boolean;
  /** Returns the front item, or undefined if empty. */
  dequeue(): T | undefined;
}
