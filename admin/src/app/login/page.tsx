// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { useState, useRef, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import Altcha from '@/components/Altcha';

export default function LoginPage() {
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [altchaToken, setAltchaToken] = useState('');
  const [altchaVerified, setAltchaVerified] = useState(false);
  const emailRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);
  const { login } = useAuth();
  const router = useRouter();

  const handleAltchaVerified = useCallback((payload: string) => {
    setAltchaToken(payload);
    setAltchaVerified(true);
  }, []);

  const handleAltchaError = useCallback(() => {
    setAltchaToken('');
    setAltchaVerified(false);
  }, []);

  const performLogin = useCallback(async () => {
    if (!altchaToken) {
      setError('Please complete the security verification');
      return;
    }

    setLoading(true);
    try {
      await login(emailRef.current?.value ?? '', passwordRef.current?.value ?? '', altchaToken);
      router.push('/');
    } catch (err: any) {
      setError(err.message || 'Login failed. Check your credentials.');
    } finally {
      setLoading(false);
    }
  }, [login, router, altchaToken]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    await performLogin();
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-warm-100">
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
                ref={emailRef}
                type="email"
                autoComplete="email"
                className="input"
                placeholder="admin@sojorn.net"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
              <input
                ref={passwordRef}
                type="password"
                autoComplete="current-password"
                className="input"
                placeholder="••••••••"
                required
              />
            </div>
            <div>
              <Altcha 
                challengeurl="https://api.sojorn.net/api/v1/admin/altcha-challenge"
                onVerified={handleAltchaVerified}
                onError={handleAltchaError}
              />
            </div>
            <button
              type="submit"
              className="btn-primary w-full"
              disabled={loading || !altchaVerified}
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
