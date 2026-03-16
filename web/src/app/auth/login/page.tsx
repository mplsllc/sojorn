'use client';

import { useState, FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/lib/auth';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import { Eye, EyeOff } from 'lucide-react';

type LoginStep = 'credentials' | 'mfa';

export default function LoginPage() {
  const { login, user, isLoading: authLoading } = useAuth();
  const router = useRouter();

  const [step, setStep] = useState<LoginStep>('credentials');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [mfaCode, setMfaCode] = useState('');
  const [mfaToken, setMfaToken] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <LoadingSpinner />
      </div>
    );
  }

  if (user) {
    router.replace('/feed');
    return null;
  }

  const handleCredentialSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setIsSubmitting(true);

    try {
      const result = await login(email, password);

      if (result.mfa_required) {
        setMfaToken(result.mfa_token ?? '');
        setStep('mfa');
      } else {
        router.push('/feed');
      }
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : 'Invalid email or password.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleMfaSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setIsSubmitting(true);

    try {
      await login(email, password, { mfa_token: mfaToken, mfa_code: mfaCode });
      router.push('/feed');
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : 'Invalid verification code.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gray-50 dark:bg-gray-950 px-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <Link
            href="/"
            className="text-2xl font-bold text-brand-600 dark:text-brand-400"
            aria-label="Back to home"
          >
            Sojorn
          </Link>
          <h1 className="mt-4 text-2xl font-bold text-gray-900 dark:text-gray-50">
            {step === 'credentials' ? 'Welcome back' : 'Two-factor authentication'}
          </h1>
          <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
            {step === 'credentials'
              ? 'Sign in to your account'
              : 'Enter the code from your authenticator app'}
          </p>
        </div>

        {error && (
          <div
            className="mb-6 rounded-lg border border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-950/50 p-3 text-sm text-red-700 dark:text-red-400"
            role="alert"
          >
            {error}
          </div>
        )}

        {step === 'credentials' ? (
          <form onSubmit={handleCredentialSubmit} className="space-y-4" noValidate>
            <div>
              <label
                htmlFor="email"
                className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
              >
                Email address
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                placeholder="you@example.com"
                aria-required="true"
              />
            </div>

            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label
                  htmlFor="password"
                  className="block text-sm font-medium text-gray-700 dark:text-gray-300"
                >
                  Password
                </label>
                <Link
                  href="/auth/forgot-password"
                  className="text-xs text-brand-600 dark:text-brand-400 hover:underline"
                >
                  Forgot password?
                </Link>
              </div>
              <div className="relative">
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 pr-10 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                  placeholder="Enter your password"
                  aria-required="true"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={isSubmitting || !email || !password}
              className="w-full rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
            >
              {isSubmitting ? (
                <span className="inline-flex items-center gap-2">
                  <LoadingSpinner />
                  Signing in...
                </span>
              ) : (
                'Sign in'
              )}
            </button>
          </form>
        ) : (
          <form onSubmit={handleMfaSubmit} className="space-y-4" noValidate>
            <div>
              <label
                htmlFor="mfa-code"
                className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
              >
                Verification code
              </label>
              <input
                id="mfa-code"
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                required
                maxLength={6}
                value={mfaCode}
                onChange={(e) =>
                  setMfaCode(e.target.value.replace(/\D/g, '').slice(0, 6))
                }
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-center tracking-[0.3em] text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                placeholder="000000"
                aria-required="true"
              />
            </div>

            <button
              type="submit"
              disabled={isSubmitting || mfaCode.length !== 6}
              className="w-full rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
            >
              {isSubmitting ? (
                <span className="inline-flex items-center gap-2">
                  <LoadingSpinner />
                  Verifying...
                </span>
              ) : (
                'Verify'
              )}
            </button>

            <button
              type="button"
              onClick={() => {
                setStep('credentials');
                setMfaCode('');
                setError('');
              }}
              className="w-full text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 transition-colors"
            >
              Back to login
            </button>
          </form>
        )}

        <p className="mt-8 text-center text-sm text-gray-600 dark:text-gray-400">
          Don&apos;t have an account?{' '}
          <Link
            href="/auth/register"
            className="font-medium text-brand-600 dark:text-brand-400 hover:underline"
          >
            Register
          </Link>
        </p>
      </div>
    </div>
  );
}
