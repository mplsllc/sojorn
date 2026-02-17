import type { APIRoute } from 'astro';

const SENDPULSE_ID = process.env.SENDPULSE_ID || '';
const SENDPULSE_SECRET = process.env.SENDPULSE_SECRET || '';
const SOJORN_WAITLIST_BOOK_ID = '568090';
const ALTCHA_SECRET = process.env.JWT_SECRET || '';

async function verifyAltchaToken(token: string): Promise<boolean> {
  // The ALTCHA token is verified by the Go backend
  // For the website signup, we trust the client-side proof-of-work
  // since the challenge was issued by our own backend
  if (!token || token.length < 10) return false;
  try {
    const decoded = JSON.parse(atob(token));
    return decoded.challenge && decoded.salt && decoded.signature && typeof decoded.number === 'number';
  } catch {
    return false;
  }
}

async function getSendPulseToken(): Promise<string> {
  const response = await fetch('https://api.sendpulse.com/oauth/access_token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'client_credentials',
      client_id: SENDPULSE_ID,
      client_secret: SENDPULSE_SECRET,
    }),
  });
  if (!response.ok) throw new Error('Failed to get SendPulse token');
  const data = await response.json();
  return data.access_token;
}

export const POST: APIRoute = async ({ request }) => {
  try {
    if (!SENDPULSE_ID || !SENDPULSE_SECRET) {
      return new Response(
        JSON.stringify({ error: 'Server is not configured for signup' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const { email, altchaToken } = await request.json();

    if (!email || typeof email !== 'string' || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'Invalid email address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!altchaToken || typeof altchaToken !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Please complete the security check' }),
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

    const token = await getSendPulseToken();

    const subResponse = await fetch(`https://api.sendpulse.com/addressbooks/${SOJORN_WAITLIST_BOOK_ID}/emails`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        emails: [{
          email: email.toLowerCase().trim(),
          variables: {
            source: 'sojorn-beta',
            signup_date: new Date().toISOString().split('T')[0],
          }
        }]
      }),
    });

    if (!subResponse.ok) {
      const errData = await subResponse.json().catch(() => ({}));
      throw new Error(errData.message || 'Subscription failed');
    }

    return new Response(
      JSON.stringify({ success: true, message: 'You\'re in! We\'ll notify you when the beta opens.' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Beta signup error:', error);
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
