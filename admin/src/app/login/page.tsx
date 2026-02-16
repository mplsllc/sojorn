'use client';

import { useState, useRef, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import Script from 'next/script';

const TURNSTILE_SITE_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY || '';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState('');
  const [turnstileReady, setTurnstileReady] = useState(false);
  const turnstileRef = useRef<HTMLDivElement>(null);
  const widgetIdRef = useRef<string | null>(null);
  const tokenRef = useRef('');
  const { login } = useAuth();
  const router = useRouter();

  // Keep ref in sync with state so the submit handler always has the latest value
  useEffect(() => { tokenRef.current = turnstileToken; }, [turnstileToken]);

  const performLogin = useCallback(async () => {
    setLoading(true);
    try {
      await login(email, password, tokenRef.current);
      router.push('/');
    } catch (err: any) {
      setError(err.message || 'Login failed. Check your credentials.');
      // Reset turnstile for retry
      refreshTurnstile();
    } finally {
      setLoading(false);
    }
  }, [email, password, tokenRef.current, login, router]);

  const renderTurnstile = useCallback(() => {
    if (!TURNSTILE_SITE_KEY || !turnstileRef.current || !(window as any).turnstile) return;
    if (widgetIdRef.current) {
      try { (window as any).turnstile.remove(widgetIdRef.current); } catch {}
    }
    widgetIdRef.current = (window as any).turnstile.render(turnstileRef.current, {
      sitekey: TURNSTILE_SITE_KEY,
      size: 'invisible',
      theme: 'light',
      callback: (token: string) => { 
      setTurnstileToken(token); 
      tokenRef.current = token; 
      setTurnstileReady(true);
      // Auto-submit after invisible verification
      performLogin(); 
    },
      'error-callback': () => { setTurnstileToken(''); tokenRef.current = ''; setTurnstileReady(false); },
      'expired-callback': () => { setTurnstileToken(''); tokenRef.current = ''; setTurnstileReady(false); },
    });
  }, [performLogin]);

  useEffect(() => {
    if ((window as any).turnstile && TURNSTILE_SITE_KEY) {
      renderTurnstile();
    }
  }, [renderTurnstile]);

  const refreshTurnstile = () => {
    setTurnstileToken('');
    tokenRef.current = '';
    setTurnstileReady(false);
    setError('');
    if (widgetIdRef.current && (window as any).turnstile) {
      (window as any).turnstile.reset(widgetIdRef.current);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (TURNSTILE_SITE_KEY && widgetIdRef.current) {
      // Trigger invisible Turnstile verification
      setLoading(true);
      try {
        (window as any).turnstile.execute(widgetIdRef.current);
        // The callback will handle the actual login
      } catch (err: any) {
        setError('Security verification failed. Please try again.');
        setLoading(false);
        refreshTurnstile();
      }
      return;
    }

    // No Turnstile or direct execution
    performLogin();
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-warm-100">
      {TURNSTILE_SITE_KEY && (
        <Script
          src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
          onReady={renderTurnstile}
        />
      )}
      <div className="w-full max-w-md">
        <div className="card p-8">
          <div className="text-center mb-8">
            <div className="w-14 h-14 bg-brand-500 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <svg className="w-8 h-8 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
            </div>
            <h1 className="text-2xl font-semibold text-gray-900">Sojorn Admin</h1>
            <p className="text-sm text-gray-500 mt-1">Sign in to manage the platform</p>
          </div>

          {error && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
              <input
                type="email"
                className="input"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="admin@sojorn.net"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
              <input
                type="password"
                className="input"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
              />
            </div>
            {/* Visible Turnstile widget */}
            {TURNSTILE_SITE_KEY && (
              <div className="flex flex-col items-center gap-2">
                <div ref={turnstileRef} />
                <button
                  type="button"
                  onClick={refreshTurnstile}
                  className="text-xs text-gray-400 hover:text-gray-600 underline"
                >
                  Refresh verification
                </button>
              </div>
            )}
            <button
              type="submit"
              className="btn-primary w-full"
              disabled={loading || (!!TURNSTILE_SITE_KEY && !turnstileReady)}
            >
              {loading ? 'Signing in...' : 'Sign In'}
            </button>
          </form>
        </div>
        <p className="text-center text-xs text-gray-400 mt-4">
          Only authorized administrators can access this panel.
        </p>
      </div>
    </div>
  );
}
