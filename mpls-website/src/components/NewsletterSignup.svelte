<script lang="ts">
  import Turnstile from './Turnstile.svelte';

  let email = '';
  let isSubmitting = false;
  let message = '';
  let messageType: 'success' | 'error' = 'success';
  let turnstileToken = '';
  let turnstileComponent: Turnstile;
  const INVALID_EMAIL_MESSAGE = 'Please enter a valid email address';

  const TURNSTILE_SITE_KEY = '0x4AAAAAACZFIzt7kzHHfSBF';

  function handleTurnstileSuccess(token: string) {
    turnstileToken = token;
    // Auto-submit after invisible Turnstile completes
    subscribe();
  }

  function resetTurnstile() {
    turnstileToken = '';
    if (turnstileComponent) {
      turnstileComponent.reset();
    }
  }

  async function subscribe() {
    // Basic email validation
    if (!email || !email.includes('@') || !email.includes('.')) {
      message = INVALID_EMAIL_MESSAGE;
      messageType = 'error';
      return;
    }

    // For invisible Turnstile, trigger it if not already completed
    if (!turnstileToken) {
      if (turnstileComponent && turnstileComponent.getResponse) {
        // Try to get the response first (in case it's already completed)
        const response = turnstileComponent.getResponse();
        if (response) {
          turnstileToken = response;
        } else {
          // Trigger the invisible Turnstile challenge
          return; // Let the Turnstile callback handle the submission
        }
      } else {
        message = 'Security verification not ready';
        messageType = 'error';
        return;
      }
    }

    isSubmitting = true;
    message = '';

    try {
      const response = await fetch('/api/newsletter', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ 
          email,
          turnstileToken 
        }),
      });

      const data = await response.json();

      if (response.ok) {
        message = 'Thank you for subscribing! Check your email for confirmation.';
        messageType = 'success';
        email = '';
        resetTurnstile();
      } else {
        message = data.error || 'Something went wrong. Please try again.';
        messageType = 'error';
        resetTurnstile();
      }
    } catch (error) {
      message = 'Network error. Please try again.';
      messageType = 'error';
      resetTurnstile();
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
        disabled={isSubmitting}
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

    <!-- Turnstile Widget -->
    <Turnstile 
      bind:this={turnstileComponent}
      sitekey={TURNSTILE_SITE_KEY}
      callback={handleTurnstileSuccess}
      theme="auto"
      size="invisible"
    />
  </form>

  {#if message}
    <div class="mt-4 p-3 rounded-lg text-sm {messageType === 'success' ? 'bg-green-50 text-green-800 border border-green-200' : 'bg-red-50 text-red-800 border border-red-200'}">
      {message}
    </div>
  {/if}
</div>
