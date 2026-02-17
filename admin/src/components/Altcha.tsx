'use client';

import { useEffect, useRef, useState } from 'react';

interface AltchaProps {
  challengeurl: string;
  onStateChange?: (state: any) => void;
}

export default function Altcha({ challengeurl, onStateChange }: AltchaProps) {
  const widgetRef = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    // Load ALTCHA widget script
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/altcha@0.5.0/dist/altcha.min.js';
    script.type = 'module';
    script.async = true;
    script.onload = () => setLoaded(true);
    document.head.appendChild(script);

    return () => {
      if (script.parentNode) {
        script.parentNode.removeChild(script);
      }
    };
  }, []);

  useEffect(() => {
    if (!loaded || !widgetRef.current) return;

    const widget = widgetRef.current.querySelector('altcha-widget');
    if (!widget) return;

    const handleStateChange = (event: any) => {
      if (onStateChange) {
        onStateChange(event.detail);
      }
    };

    widget.addEventListener('statechange', handleStateChange);

    return () => {
      widget.removeEventListener('statechange', handleStateChange);
    };
  }, [loaded, onStateChange]);

  return (
    <div ref={widgetRef}>
      <altcha-widget
        challengeurl={challengeurl}
        hidefooter="true"
        hidelogo="true"
      />
    </div>
  );
}
