// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

import type { APIRoute } from 'astro';

const SOJORN_API_URL = process.env.SOJORN_API_URL || 'https://api.sojorn.net';

async function verifyAltchaToken(token: string): Promise<boolean> {
  if (!token || token.length < 10) return false;
  try {
    const decoded = JSON.parse(atob(token));
    const { challenge, number, salt } = decoded;
    if (!challenge || typeof number !== 'number' || !salt) return false;
    // Verify proof-of-work: SHA-256(salt + number) === challenge
    const encoded = new TextEncoder().encode(String(salt) + String(number));
    const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
    const hashHex = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    return hashHex === challenge;
  } catch {
    return false;
  }
}

export const POST: APIRoute = async ({ request }) => {
  try {
    const { email, altchaToken } = await request.json();

    if (!email || typeof email !== 'string' || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'Invalid email address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!altchaToken || typeof altchaToken !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Security verification required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const isValid = await verifyAltchaToken(altchaToken);
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
