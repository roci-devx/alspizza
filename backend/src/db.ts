import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();

/** Atomically increments a named counter (used for human-friendly order numbers). */
export async function nextCounter(id: string, start: number): Promise<number> {
  const row = await prisma.counter.upsert({
    where: { id },
    update: { value: { increment: 1 } },
    create: { id, value: start },
  });
  return row.value;
}

export const json = {
  parse<T>(value: string | null | undefined, fallback: T): T {
    if (!value) return fallback;
    try {
      return JSON.parse(value) as T;
    } catch {
      return fallback;
    }
  },
};
