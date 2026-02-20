import type { APIRoute } from 'astro';

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { email, handle, request_type, details, clear_types } = body;

    if (!email || !handle || !request_type) {
      return new Response(JSON.stringify({ error: 'Email, handle, and request type are required.' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (!['delete_account', 'clear_data'].includes(request_type)) {
      return new Response(JSON.stringify({ error: 'Invalid request type.' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Get SendPulse access token
    const spId = process.env.SENDPULSE_ID;
    const spSecret = process.env.SENDPULSE_SECRET;

    if (!spId || !spSecret) {
      console.error('SendPulse credentials not configured');
      return new Response(JSON.stringify({ error: 'Email service not configured. Please email privacy@sojorn.net directly.' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const tokenRes = await fetch('https://api.sendpulse.com/oauth/access_token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        grant_type: 'client_credentials',
        client_id: spId,
        client_secret: spSecret,
      }),
    });

    if (!tokenRes.ok) {
      console.error('SendPulse auth failed:', await tokenRes.text());
      return new Response(JSON.stringify({ error: 'Email service error. Please email privacy@sojorn.net directly.' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const { access_token } = await tokenRes.json();

    // Build email body
    const typeLabel = request_type === 'delete_account' ? 'Account Deletion' : 'Data Clearing';
    const clearList = clear_types?.length ? `\nData to clear: ${clear_types.join(', ')}` : '';

    const htmlBody = `
      <h2>Sojorn ${typeLabel} Request</h2>
      <table style="border-collapse:collapse;width:100%;max-width:500px;">
        <tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #eee;">Type</td><td style="padding:8px;border-bottom:1px solid #eee;">${typeLabel}</td></tr>
        <tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #eee;">Email</td><td style="padding:8px;border-bottom:1px solid #eee;">${email}</td></tr>
        <tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #eee;">Handle</td><td style="padding:8px;border-bottom:1px solid #eee;">${handle}</td></tr>
        ${clear_types?.length ? `<tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #eee;">Clear</td><td style="padding:8px;border-bottom:1px solid #eee;">${clear_types.join(', ')}</td></tr>` : ''}
        <tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #eee;">Details</td><td style="padding:8px;border-bottom:1px solid #eee;">${details || '(none)'}</td></tr>
        <tr><td style="padding:8px;font-weight:bold;">Submitted</td><td style="padding:8px;">${new Date().toISOString()}</td></tr>
      </table>
    `;

    // Send email via SendPulse SMTP
    const emailRes = await fetch('https://api.sendpulse.com/smtp/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${access_token}`,
      },
      body: JSON.stringify({
        email: {
          subject: `[Sojorn] ${typeLabel} Request — ${handle}`,
          from: { name: 'Sojorn Data Requests', email: 'privacy@sojorn.net' },
          to: [{ name: 'Sojorn Team', email: 'contact@sojorn.net' }],
          html: htmlBody,
        },
      }),
    });

    if (!emailRes.ok) {
      console.error('SendPulse email failed:', await emailRes.text());
      return new Response(JSON.stringify({ error: 'Failed to send request. Please email privacy@sojorn.net directly.' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ success: true, message: 'Request submitted successfully.' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (err) {
    console.error('Data request error:', err);
    return new Response(JSON.stringify({ error: 'Server error. Please email privacy@sojorn.net directly.' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
};
