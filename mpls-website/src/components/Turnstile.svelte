<script lang="ts">
  import { onMount } from 'svelte';

  export let sitekey: string;
  export let callback: (token: string) => void;
  export let theme: 'light' | 'dark' | 'auto' = 'auto';
  export let size: 'normal' | 'compact' | 'invisible' = 'normal';

  let widgetId: string | null = null;
  let containerElement: HTMLDivElement;

  onMount(() => {
    // Load Turnstile script if not already loaded
    if (!window.turnstile) {
      const script = document.createElement('script');
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
      script.async = true;
      script.defer = true;
      document.head.appendChild(script);

      script.onload = () => {
        initTurnstile();
      };
    } else {
      initTurnstile();
    }

    return () => {
      // Cleanup widget when component is destroyed
      if (widgetId && window.turnstile) {
        window.turnstile.remove(widgetId);
      }
    };
  });

  function initTurnstile() {
    if (!window.turnstile || !containerElement) return;

    const config = {
      sitekey: sitekey,
      callback: callback,
      theme: theme,
      size: size,
      'refresh-expired': 'auto',
    };

    // For invisible mode, we need to add the action parameter
    if (size === 'invisible') {
      config['action'] = 'submit';
    }

    widgetId = window.turnstile.render(containerElement, config);
  }

  // Expose reset function for external use
  export function reset() {
    if (widgetId && window.turnstile) {
      window.turnstile.reset(widgetId);
    }
  }

  // Expose getResponse function for external use
  export function getResponse(): string | undefined {
    if (widgetId && window.turnstile) {
      return window.turnstile.getResponse(widgetId);
    }
    return undefined;
  }
</script>

<!-- Turnstile container -->
<div bind:this={containerElement} class="turnstile-container"></div>

<style>
  .turnstile-container {
    margin: 0.5rem 0;
  }
  
  /* Responsive adjustments */
  @media (max-width: 640px) {
    .turnstile-container {
      transform: scale(0.9);
      transform-origin: left center;
    }
  }
</style>
