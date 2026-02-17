'use client';

import { useEffect, useRef, useCallback } from 'react';

interface AltchaProps {
  challengeurl: string;
  onVerified?: (payload: string) => void;
  onError?: () => void;
}

export default function Altcha({ challengeurl, onVerified, onError }: AltchaProps) {
  const widgetRef = useRef<HTMLDivElement>(null);
  const scriptLoaded = useRef(false);

  const handleStateChange = useCallback((e: Event) => {
    const detail = (e as CustomEvent).detail;
    if (detail?.state === 'verified' && detail?.payload) {
      onVerified?.(detail.payload);
    } else if (detail?.state === 'error') {
      onError?.();
    }
  }, [onVerified, onError]);

  useEffect(() => {
    if (scriptLoaded.current) return;
    scriptLoaded.current = true;

    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/altcha@2.3.0/dist/altcha.min.js';
    script.type = 'module';
    script.async = true;
    document.head.appendChild(script);
  }, []);

  useEffect(() => {
    const container = widgetRef.current;
    if (!container) return;

    const observer = new MutationObserver(() => {
      const widget = container.querySelector('altcha-widget');
      if (widget) {
        widget.addEventListener('statechange', handleStateChange);
        observer.disconnect();
      }
    });

    observer.observe(container, { childList: true, subtree: true });

    // Also try immediately in case widget already exists
    const widget = container.querySelector('altcha-widget');
    if (widget) {
      widget.addEventListener('statechange', handleStateChange);
      observer.disconnect();
    }

    return () => {
      observer.disconnect();
      const w = container.querySelector('altcha-widget');
      if (w) {
        w.removeEventListener('statechange', handleStateChange);
      }
    };
  }, [handleStateChange]);

  return (
    <div ref={widgetRef} dangerouslySetInnerHTML={{
      __html: `<altcha-widget challengeurl="${challengeurl}" debug></altcha-widget>`
    }} />
  );
}

