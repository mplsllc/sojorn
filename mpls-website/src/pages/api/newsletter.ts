import type { APIRoute } from 'astro';

// Validate required environment variables
const SENDPULSE_ID = process.env.SENDPULSE_ID;
const SENDPULSE_SECRET = process.env.SENDPULSE_SECRET;
const MPLS_ADDRESS_BOOK_ID = process.env.MPLS_ADDRESS_BOOK_ID || '1';
const SOJORN_WAITLIST_ADDRESS_BOOK_ID = process.env.SOJORN_WAITLIST_ADDRESS_BOOK_ID;
const SOJORN_WAITLIST_ADDRESS_BOOK_NAME = (process.env.SOJORN_WAITLIST_ADDRESS_BOOK_NAME || 'Sojorn Waitlist').toLowerCase();
const SOJORN_FROM_EMAIL = process.env.SOJORN_FROM_EMAIL || 'hello@mp.ls';
const SOJORN_FROM_NAME = process.env.SOJORN_FROM_NAME || 'Sojorn';
const SENDPULSE_THANK_YOU_MODE = (process.env.SENDPULSE_THANK_YOU_MODE || 'automation').toLowerCase();
const SENDPULSE_A360_EVENT_NAME = process.env.SENDPULSE_A360_EVENT_NAME || 'sojorn_waitlist_signup';
const SENDPULSE_A360_AUTOMATION_ID = process.env.SENDPULSE_A360_AUTOMATION_ID;
const SENDPULSE_A360_EVENT_URL = process.env.SENDPULSE_A360_EVENT_URL;

if (!SENDPULSE_ID || !SENDPULSE_SECRET) {
  throw new Error('Missing required environment variables: SENDPULSE_ID, SENDPULSE_SECRET');
}

interface SendPulseTokenResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
}

interface SendPulseAddressBook {
  id: number;
  name: string;
  emails: number;
}

interface SendPulseSubscribeResponse {
  result: boolean;
  error?: string;
}

interface SendPulseSmtpResponse {
  result: boolean;
  id?: string;
  error?: string;
}

interface SendPulseAutomationEventResponse {
  result?: boolean;
  message?: string;
  error?: string;
}

async function verifyAltchaToken(token: string): Promise<boolean> {
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
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      grant_type: 'client_credentials',
      client_id: SENDPULSE_ID,
      client_secret: SENDPULSE_SECRET,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error('SendPulse token error:', errorText);
    throw new Error('Failed to get SendPulse access token');
  }

  const data: SendPulseTokenResponse = await response.json();
  return data.access_token;
}

async function getAddressBooks(token: string): Promise<SendPulseAddressBook[]> {
  const response = await fetch('https://api.sendpulse.com/addressbooks', {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error('Failed to get address books');
  }

  return response.json();
}

async function subscribeToSendPulse(email: string, token: string): Promise<void> {
  let addressBookId = SOJORN_WAITLIST_ADDRESS_BOOK_ID || MPLS_ADDRESS_BOOK_ID;

  try {
    const addressBooks = await getAddressBooks(token);

    const sojornWaitlist = addressBooks.find((book) => {
      const normalized = book.name.toLowerCase();
      return normalized === SOJORN_WAITLIST_ADDRESS_BOOK_NAME || (normalized.includes('sojorn') && normalized.includes('waitlist'));
    });

    if (sojornWaitlist) {
      addressBookId = sojornWaitlist.id.toString();
      console.log(`Using Sojorn waitlist address book: ${sojornWaitlist.name} (ID: ${addressBookId})`);
    } else if (!addressBooks.find((book) => book.id.toString() === addressBookId) && addressBooks.length > 0) {
      addressBookId = addressBooks[0].id.toString();
      console.log(`Sojorn waitlist not found. Using fallback address book: ${addressBooks[0].name} (ID: ${addressBookId})`);
    }
  } catch (error) {
    console.warn('Could not fetch address books, using configured fallback ID');
  }

  const response = await fetch(`https://api.sendpulse.com/addressbooks/${addressBookId}/emails`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      emails: [
        {
          email: email,
          variables: {
            source: 'sojorn-beta',
            subscribed_date: new Date().toISOString()
          }
        }
      ]
    }),
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    const errorMessage = errorData.error || errorData.message || 'Failed to subscribe to newsletter';
    throw new Error(errorMessage);
  }

  const data: SendPulseSubscribeResponse = await response.json();
  if (!data.result) {
    throw new Error(data.error || 'Subscription failed');
  }
}

function getSojornThankYouTemplate(email: string): string {
  return `
  <div style="margin:0;padding:0;background:#0a0a0a;font-family:Inter,Segoe UI,Arial,sans-serif;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:24px 12px;background:#0a0a0a;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#111827;border:1px solid #1f2937;border-radius:16px;overflow:hidden;">
            <tr>
              <td style="padding:28px 24px 12px;text-align:center;">
                <img src="https://mp.ls/img/sojornlogo.png" alt="Sojorn" width="88" style="display:block;margin:0 auto 12px;" />
                <h1 style="margin:0;color:#ffffff;font-size:28px;line-height:1.2;font-weight:800;">You're on the waitlist</h1>
                <p style="margin:10px 0 0;color:#cbd5e1;font-size:15px;line-height:1.6;">Thanks for requesting early access to Sojorn.</p>
              </td>
            </tr>
            <tr>
              <td style="padding:12px 24px 24px;">
                <div style="background:#0f172a;border:1px solid #1e293b;border-radius:12px;padding:14px 16px;">
                  <p style="margin:0;color:#e2e8f0;font-size:14px;line-height:1.6;">
                    We received your signup for <strong>${email}</strong> and will email you when your invite is ready.
                  </p>
                </div>
                <p style="margin:16px 0 0;color:#94a3b8;font-size:13px;line-height:1.6;">
                  Sojorn is built around private communication, no tracking, and data sovereignty.
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </div>`;
}

async function sendThankYouEmail(email: string, token: string): Promise<void> {
  const response = await fetch('https://api.sendpulse.com/smtp/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email: {
        subject: 'Thanks for joining the Sojorn waitlist',
        html: getSojornThankYouTemplate(email),
        text: `Thanks for joining the Sojorn waitlist. We received your signup for ${email} and will email you when your invite is ready.`,
        from: {
          name: SOJORN_FROM_NAME,
          email: SOJORN_FROM_EMAIL,
        },
        to: [
          {
            email,
          },
        ],
      },
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to send thank-you email: ${errorText}`);
  }

  const data: SendPulseSmtpResponse = await response.json();
  if (!data.result) {
    throw new Error(data.error || 'Failed to send thank-you email');
  }
}

async function triggerSojornAutomationEvent(email: string, token: string): Promise<void> {
  const eventName = encodeURIComponent(SENDPULSE_A360_EVENT_NAME);
  const payload: Record<string, string | number> = {
    email,
    source: 'sojorn-beta',
    event_date: new Date().toISOString().slice(0, 10),
    subscribed_at: new Date().toISOString(),
  };

  if (SENDPULSE_A360_AUTOMATION_ID) {
    const parsedAutomationId = Number(SENDPULSE_A360_AUTOMATION_ID);
    if (Number.isFinite(parsedAutomationId)) {
      payload.automation_id = parsedAutomationId;
    }
  }

  const eventEndpoint = SENDPULSE_A360_EVENT_URL || `https://api.sendpulse.com/events/name/${eventName}`;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };

  if (!SENDPULSE_A360_EVENT_URL) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(eventEndpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to trigger automation event: ${errorText}`);
  }

  const data: SendPulseAutomationEventResponse = await response.json().catch(() => ({}));
  if (data.result === false) {
    throw new Error(data.error || data.message || 'Failed to trigger automation event');
  }
}

async function runThankYouFlow(email: string, token: string): Promise<void> {
  if (SENDPULSE_THANK_YOU_MODE === 'none') {
    return;
  }

  if (SENDPULSE_THANK_YOU_MODE === 'smtp') {
    await sendThankYouEmail(email, token);
    return;
  }

  try {
    await triggerSojornAutomationEvent(email, token);
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    if (message.includes('Event not exists')) {
      console.warn(`Automation event '${SENDPULSE_A360_EVENT_NAME}' does not exist. Falling back to SMTP thank-you email.`);
      await sendThankYouEmail(email, token);
      return;
    }

    throw error;
  }
}

export const POST: APIRoute = async ({ request }) => {
  try {
    const { email, altchaToken } = await request.json();

    // Validate email
    if (!email || typeof email !== 'string' || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'Invalid email address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Validate ALTCHA token
    if (!altchaToken || typeof altchaToken !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Security verification required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Verify ALTCHA proof-of-work token
    const isValid = await verifyAltchaToken(altchaToken);
    if (!isValid) {
      return new Response(
        JSON.stringify({ error: 'Security verification failed. Please try again.' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Get SendPulse token
    const token = await getSendPulseToken();

    // Subscribe to newsletter
    await subscribeToSendPulse(email.toLowerCase().trim(), token);

    // Send follow-up flow (non-blocking for waitlist success)
    try {
      await runThankYouFlow(email.toLowerCase().trim(), token);
    } catch (emailError) {
      console.error('Thank-you flow error:', emailError);
    }

    return new Response(
      JSON.stringify({ success: true, message: 'Successfully subscribed to newsletter' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Newsletter subscription error:', error);

    const userMessage = error instanceof Error && error.message.includes('already exists')
      ? 'This email is already subscribed to our newsletter.'
      : 'Failed to subscribe. Please try again later.';

    return new Response(
      JSON.stringify({ error: userMessage }),
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
