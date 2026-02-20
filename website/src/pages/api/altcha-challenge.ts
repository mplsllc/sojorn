import type { APIRoute } from 'astro';
import { createChallenge } from 'altcha-lib';

export const GET: APIRoute = async () => {
  const hmacKey = process.env.ALTCHA_SECRET || process.env.JWT_SECRET || 'dev-secret';

  const challenge = await createChallenge({
    hmacKey,
    algorithm: 'SHA-256',
    maxNumber: 100000,
    saltLength: 12,
  });

  return new Response(JSON.stringify(challenge), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
