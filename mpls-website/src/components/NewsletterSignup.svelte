<script lang="ts">
  import { onMount } from 'svelte';

  let email = '';
  let isSubmitting = false;
  let message = '';
  let messageType: 'success' | 'error' = 'success';
  let altchaToken: string | null = null;
  let altchaStatus: 'loading' | 'ready' | 'error' = 'loading';
  const INVALID_EMAIL_MESSAGE = 'Please enter a valid email address';

  async function solveAltcha(): Promise<string | null> {
    try {
      const res = await fetch('https://api.sojorn.net/api/v1/auth/altcha-challenge');
      if (!res.ok) return null;
      const data = await res.json();
      const challenge = data.challenge;
      const salt = data.salt;
      const algorithm = data.algorithm || 'SHA-256';
      const signature = data.signature;
      const maxNumber = data.maxnumber || 100000;

      for (let n = 0; n <= maxNumber; n++) {
        const input = salt + n;
        const encoded = new TextEncoder().encode(input);
        const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        const hashHex = hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
        if (hashHex === challenge) {
          const payload = JSON.stringify({ algorithm, challenge, number: n, salt, signature });
          return btoa(payload);
        }
      }
      return null;
    } catch {
      return null;
    }
  }

  onMount(() => {
    solveAltcha().then((token) => {
      if (token) {
        altchaToken = token;
        altchaStatus = 'ready';
      } else {
        altchaStatus = 'error';
      }
    });
  });

  async function subscribe() {
    if (!email || !email.includes('@') || !email.includes('.')) {
      message = INVALID_EMAIL_MESSAGE;
      messageType = 'error';
      return;
    }

    if (!altchaToken) {
      message = 'Security verification not ready. Please wait or reload the page.';
      messageType = 'error';
      return;
    }

    isSubmitting = true;
    message = '';

    try {
      const response = await fetch('/api/newsletter', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, altchaToken }),
      });

      const data = await response.json();

      if (response.ok) {
        message = "You're in! We'll notify you when the beta opens.";
        messageType = 'success';
        email = '';
        // Re-solve for next submission
        altchaToken = null;
        altchaStatus = 'loading';
        solveAltcha().then((token) => {
          if (token) {
            altchaToken = token;
            altchaStatus = 'ready';
          } else {
            altchaStatus = 'error';
          }
        });
      } else {
        message = data.error || 'Something went wrong. Please try again.';
        messageType = 'error';
      }
    } catch {
      message = 'Network error. Please try again.';
      messageType = 'error';
    } finally {
      isSubmitting = false;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      e.preventDefault();
      subscribe();
    }
  }
</script>

<div class="w-full max-w-md mx-auto">
  <form on:submit|preventDefault={subscribe} class="space-y-4">
    <div class="flex flex-col sm:flex-row gap-3">
      <input
        type="email"
        bind:value={email}
        placeholder="Enter your email"
        class="flex-1 px-4 py-3 rounded-lg border border-zinc-300 bg-white text-zinc-900 placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-brand-700 focus:border-transparent transition-all"
        disabled={isSubmitting}
        on:input={() => {
          if (message === INVALID_EMAIL_MESSAGE) {
            message = '';
          }
        }}
        on:keydown={handleKeydown}
        required
      />
      <button
        type="submit"
        disabled={isSubmitting || altchaStatus !== 'ready'}
        class="px-6 py-3 rounded-lg bg-brand-700 text-white font-semibold hover:bg-brand-800 focus:outline-none focus:ring-2 focus:ring-brand-700 focus:ring-offset-2 transition-all disabled:opacity-50 disabled:cursor-not-allowed whitespace-nowrap"
      >
        {#if isSubmitting}
          <span class="flex items-center gap-2">
            <svg class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Subscribing...
          </span>
        {:else}
          Subscribe
        {/if}
      </button>
    </div>

    <p class="text-xs text-zinc-600 leading-relaxed">
      By clicking <span class="font-semibold">Subscribe</span>, you agree to the <a href="/terms" target="_blank" rel="noopener noreferrer" class="underline underline-offset-2 hover:text-zinc-800">Terms of Use</a> and consent to receive beta signup emails.
    </p>

    <!-- ALTCHA verification status -->
    <div class="my-1">
      {#if altchaStatus === 'loading'}
        <p class="text-xs text-zinc-500">Verifying...</p>
      {:else if altchaStatus === 'ready'}
        <p class="text-xs text-green-600">&#10003; Verified</p>
      {:else}
        <p class="text-xs text-red-500">Verification failed. <button type="button" on:click={() => location.reload()} class="underline">Retry</button></p>
      {/if}
    </div>
  </form>

  {#if message}
    <div class="mt-4 p-3 rounded-lg text-sm {messageType === 'success' ? 'bg-green-50 text-green-800 border border-green-200' : 'bg-red-50 text-red-800 border border-red-200'}">
      {message}
    </div>
  {/if}
</div>
