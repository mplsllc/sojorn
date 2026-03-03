// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

import type { APIRoute } from 'astro';

const TURNSTILE_SECRET = process.env.TURNSTILE_SECRET;
const SOJORN_API_URL = process.env.SOJORN_API_URL || 'https://api.sojorn.net';

if (!TURNSTILE_SECRET) {
  throw new Error('Missing required environment variable: TURNSTILE_SECRET');
}

async function verifyTurnstileToken(token: string): Promise<boolean> {
  const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `secret=${encodeURIComponent(TURNSTILE_SECRET as string)}&response=${encodeURIComponent(token)}`,
  });
  if (!response.ok) return false;
  const data = await response.json();
  return data.success === true;
}

export const POST: APIRoute = async ({ request }) => {
  try {
    const { email, turnstileToken } = await request.json();

    if (!email || typeof email !== 'string' || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'Invalid email address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!turnstileToken || typeof turnstileToken !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Security verification required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const isValid = await verifyTurnstileToken(turnstileToken);
    if (!isValid) {
      return new Response(
        JSON.stringify({ error: 'Security verification failed. Please try again.' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const waitlistRes = await fetch(`${SOJORN_API_URL}/api/v1/waitlist`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.toLowerCase().trim() }),
    });

    if (!waitlistRes.ok) {
      const errData = await waitlistRes.json().catch(() => ({}));
      throw new Error((errData as { error?: string }).error || 'Failed to join waitlist');
    }

    return new Response(
      JSON.stringify({ success: true, message: "You're on the list! We'll email you when access opens." }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Waitlist signup error:', error);
    return new Response(
      JSON.stringify({ error: 'Something went wrong. Please try again.' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
};

export const GET: APIRoute = () => {
  return new Response(
    JSON.stringify({ error: 'Method not allowed' }),
    { status: 405, headers: { 'Content-Type': 'application/json' } }
  );
};
