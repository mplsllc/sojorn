// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { useEffect, useRef } from 'react';

interface AltchaProps {
  challengeurl: string;
  onVerified?: (payload: string) => void;
  onError?: () => void;
}

export default function Altcha({ challengeurl, onVerified, onError }: AltchaProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const callbacksRef = useRef({ onVerified, onError });
  callbacksRef.current = { onVerified, onError };

  useEffect(() => {
    // Load script if not already loaded
    if (!document.querySelector('script[data-altcha]')) {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/altcha@2.3.0/dist/altcha.min.js';
      script.type = 'module';
      script.async = true;
      script.setAttribute('data-altcha', 'true');
      document.head.appendChild(script);
    }

    const container = containerRef.current;
    if (!container) return;

    // Create the widget element
    container.innerHTML = `<altcha-widget challengeurl="${challengeurl}"></altcha-widget>`;
    const widget = container.querySelector('altcha-widget');
    if (!widget) return;

    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      console.log('[ALTCHA] statechange:', detail);
      if (detail?.state === 'verified' && detail?.payload) {
        callbacksRef.current.onVerified?.(detail.payload);
      } else if (detail?.state === 'error') {
        callbacksRef.current.onError?.();
      }
    };

    widget.addEventListener('statechange', handler);

    return () => {
      widget.removeEventListener('statechange', handler);
    };
  }, [challengeurl]);

  return <div ref={containerRef} />;
}

