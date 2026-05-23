import { NextResponse } from 'next/server';

/**
 * Liveness probe. Intentionally minimal — does not touch Supabase, Upstash,
 * or any external API, so it remains useful even when downstream services
 * are unavailable.
 */
export const dynamic = 'force-dynamic';

export function GET() {
  return NextResponse.json({ status: 'ok' });
}
