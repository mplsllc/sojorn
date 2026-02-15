import type { APIRoute } from 'astro';

const SENDPULSE_ID = process?.env?.SENDPULSE_ID || '';
const SENDPULSE_SECRET = process?.env?.SENDPULSE_SECRET || '';
const MPLS_ADDRESS_BOOK_ID = process?.env?.MPLS_ADDRESS_BOOK_ID || '1'; // Will be updated after creating the MPLS list
const TURNSTILE_SECRET = process?.env?.TURNSTILE_SECRET || '';

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

interface TurnstileResponse {
  success: boolean;
  'error-codes'?: string[];
  challenge_ts?: string;
  hostname?: string;
}

async function verifyTurnstileToken(token: string): Promise<boolean> {
  const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: `secret=${encodeURIComponent(TURNSTILE_SECRET)}&response=${encodeURIComponent(token)}`,
  });

  if (!response.ok) {
    throw new Error('Failed to verify Turnstile token');
  }

  const data: TurnstileResponse = await response.json();
  return data.success;
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
  // Try to use the MPLS address book, or get the first available one
  let addressBookId = MPLS_ADDRESS_BOOK_ID;
  
  try {
    const addressBooks = await getAddressBooks(token);
    
    // Look for MPLS-specific address book first
    const mplsBook = addressBooks.find(book => 
      book.name.toLowerCase().includes('mpls') || 
      book.name.toLowerCase().includes('website')
    );
    
    if (mplsBook) {
      addressBookId = mplsBook.id.toString();
      console.log(`Using MPLS address book: ${mplsBook.name} (ID: ${addressBookId})`);
    } else if (!addressBooks.find(book => book.id.toString() === addressBookId) && addressBooks.length > 0) {
      // If the specified ID doesn't exist, use the first available address book
      addressBookId = addressBooks[0].id.toString();
      console.log(`Using default address book: ${addressBooks[0].name} (ID: ${addressBookId})`);
    }
  } catch (error) {
    console.warn('Could not fetch address books, using default ID');
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
            source: 'mpls-website',
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

export const POST: APIRoute = async ({ request }) => {
  try {
    if (!SENDPULSE_ID || !SENDPULSE_SECRET || !TURNSTILE_SECRET) {
      return new Response(
        JSON.stringify({ error: 'Server is not configured for newsletter signup' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const { email, turnstileToken } = await request.json();

    // Validate email
    if (!email || typeof email !== 'string' || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'Invalid email address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Validate Turnstile token
    if (!turnstileToken || typeof turnstileToken !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Security verification required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Verify Turnstile token
    const isValidTurnstile = await verifyTurnstileToken(turnstileToken);
    if (!isValidTurnstile) {
      return new Response(
        JSON.stringify({ error: 'Security verification failed. Please try again.' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Get SendPulse token
    const token = await getSendPulseToken();

    // Subscribe to newsletter
    await subscribeToSendPulse(email.toLowerCase().trim(), token);

    return new Response(
      JSON.stringify({ success: true, message: 'Successfully subscribed to newsletter' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Newsletter subscription error:', error);
    
    // Don't expose detailed error messages to the client
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
