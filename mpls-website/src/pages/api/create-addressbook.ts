import type { APIRoute } from 'astro';

// Validate required environment variables
const SENDPULSE_ID = process.env.SENDPULSE_ID;
const SENDPULSE_SECRET = process.env.SENDPULSE_SECRET;

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

interface CreateAddressBookResponse {
  id: number;
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

async function createAddressBook(token: string, name: string): Promise<number> {
  const response = await fetch('https://api.sendpulse.com/addressbooks', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      name: name,
    }),
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.error || 'Failed to create address book');
  }

  const data: CreateAddressBookResponse = await response.json();
  return data.id;
}

async function listAddressBooks(token: string): Promise<SendPulseAddressBook[]> {
  const response = await fetch('https://api.sendpulse.com/addressbooks', {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error('Failed to list address books');
  }

  return response.json();
}

export const POST: APIRoute = async ({ request }) => {
  try {
    const { name } = await request.json();

    if (!name || typeof name !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Address book name is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const token = await getSendPulseToken();
    
    // First, check if an address book with this name already exists
    const existingBooks = await listAddressBooks(token);
    const existingBook = existingBooks.find(book => book.name.toLowerCase() === name.toLowerCase());
    
    if (existingBook) {
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Address book already exists',
          addressBook: existingBook
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Create new address book
    const addressBookId = await createAddressBook(token, name);

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Address book created successfully',
        addressBookId: addressBookId
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Create address book error:', error);
    
    return new Response(
      JSON.stringify({ 
        error: error instanceof Error ? error.message : 'Failed to create address book' 
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
};

export const GET: APIRoute = async () => {
  try {
    const token = await getSendPulseToken();
    const addressBooks = await listAddressBooks(token);

    return new Response(
      JSON.stringify({ 
        success: true, 
        addressBooks: addressBooks 
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('List address books error:', error);
    
    return new Response(
      JSON.stringify({ 
        error: error instanceof Error ? error.message : 'Failed to list address books' 
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
};
