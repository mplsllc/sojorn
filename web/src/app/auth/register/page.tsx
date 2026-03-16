'use client';

import { useState, useEffect, FormEvent, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/lib/auth';
import { api } from '@/lib/api';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import { Eye, EyeOff, Check, X } from 'lucide-react';

type RegisterStep = 'form' | 'check-email';

interface PasswordCheck {
  label: string;
  met: boolean;
}

function getPasswordStrength(password: string): {
  score: number;
  checks: PasswordCheck[];
} {
  const checks: PasswordCheck[] = [
    { label: 'At least 8 characters', met: password.length >= 8 },
    { label: 'Contains uppercase letter', met: /[A-Z]/.test(password) },
    { label: 'Contains lowercase letter', met: /[a-z]/.test(password) },
    { label: 'Contains a number', met: /\d/.test(password) },
    {
      label: 'Contains special character',
      met: /[^A-Za-z0-9]/.test(password),
    },
  ];
  const score = checks.filter((c) => c.met).length;
  return { score, checks };
}

function strengthLabel(score: number): { text: string; color: string } {
  if (score <= 1) return { text: 'Weak', color: 'bg-red-500' };
  if (score <= 2) return { text: 'Fair', color: 'bg-orange-500' };
  if (score <= 3) return { text: 'Good', color: 'bg-yellow-500' };
  if (score <= 4) return { text: 'Strong', color: 'bg-green-500' };
  return { text: 'Very strong', color: 'bg-emerald-500' };
}

export default function RegisterPage() {
  const { register, user, isLoading: authLoading } = useAuth();
  const router = useRouter();

  const [step, setStep] = useState<RegisterStep>('form');
  const [handle, setHandle] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [inviteToken, setInviteToken] = useState('');
  const [acceptTerms, setAcceptTerms] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showInvite, setShowInvite] = useState(false);
  const [requiresInvite, setRequiresInvite] = useState(false);
  const [error, setError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    api
      .getInstance()
      .then((instance: { approval_required?: boolean; invite_required?: boolean }) => {
        if (instance.invite_required) {
          setRequiresInvite(true);
          setShowInvite(true);
        }
      })
      .catch(() => {});
  }, []);

  const passwordStrength = useMemo(() => getPasswordStrength(password), [password]);
  const strengthInfo = useMemo(
    () => strengthLabel(passwordStrength.score),
    [passwordStrength.score]
  );

  const passwordsMatch = confirmPassword.length > 0 && password === confirmPassword;
  const passwordsMismatch = confirmPassword.length > 0 && password !== confirmPassword;

  const canSubmit =
    handle.length >= 2 &&
    email.includes('@') &&
    passwordStrength.score >= 3 &&
    passwordsMatch &&
    acceptTerms &&
    (!requiresInvite || inviteToken.length > 0);

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

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;
    setError('');
    setIsSubmitting(true);

    try {
      await register({
        handle,
        email,
        password,
        invite_token: inviteToken || undefined,
      });
      setStep('check-email');
    } catch (err: unknown) {
      const message =
        err instanceof Error
          ? err.message
          : 'Registration failed. Please try again.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  if (step === 'check-email') {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-gray-50 dark:bg-gray-950 px-4">
        <div className="w-full max-w-sm text-center">
          <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/40 mb-6">
            <Check className="h-8 w-8 text-brand-600 dark:text-brand-400" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-50">
            Check your email
          </h1>
          <p className="mt-3 text-sm text-gray-600 dark:text-gray-400 leading-relaxed">
            We sent a confirmation link to{' '}
            <span className="font-medium text-gray-900 dark:text-gray-100">
              {email}
            </span>
            . Click the link in your email to activate your account.
          </p>
          <div className="mt-8 space-y-3">
            <Link
              href="/auth/login"
              className="block w-full rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 transition-colors text-center focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
            >
              Go to login
            </Link>
            <Link
              href="/"
              className="block w-full text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 transition-colors text-center py-2"
            >
              Back to home
            </Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gray-50 dark:bg-gray-950 px-4 py-12">
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
            Create your account
          </h1>
          <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Join the conversation
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

        <form onSubmit={handleSubmit} className="space-y-4" noValidate>
          <div>
            <label
              htmlFor="handle"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
            >
              Handle
            </label>
            <div className="relative">
              <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-sm text-gray-400">
                @
              </span>
              <input
                id="handle"
                type="text"
                autoComplete="username"
                required
                value={handle}
                onChange={(e) =>
                  setHandle(
                    e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '')
                  )
                }
                maxLength={30}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 pl-8 pr-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                placeholder="yourhandle"
                aria-required="true"
              />
            </div>
          </div>

          <div>
            <label
              htmlFor="reg-email"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
            >
              Email address
            </label>
            <input
              id="reg-email"
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
            <label
              htmlFor="reg-password"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
            >
              Password
            </label>
            <div className="relative">
              <input
                id="reg-password"
                type={showPassword ? 'text' : 'password'}
                autoComplete="new-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 pr-10 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                placeholder="Create a strong password"
                aria-required="true"
                aria-describedby="password-strength"
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

            {password.length > 0 && (
              <div id="password-strength" className="mt-2 space-y-2">
                <div className="flex items-center gap-2">
                  <div className="flex-1 flex gap-1">
                    {[1, 2, 3, 4, 5].map((i) => (
                      <div
                        key={i}
                        className={`h-1.5 flex-1 rounded-full transition-colors ${
                          i <= passwordStrength.score
                            ? strengthInfo.color
                            : 'bg-gray-200 dark:bg-gray-700'
                        }`}
                      />
                    ))}
                  </div>
                  <span className="text-xs text-gray-500 dark:text-gray-400 min-w-[70px] text-right">
                    {strengthInfo.text}
                  </span>
                </div>
                <ul className="space-y-1" aria-label="Password requirements">
                  {passwordStrength.checks.map((check) => (
                    <li
                      key={check.label}
                      className={`flex items-center gap-1.5 text-xs ${
                        check.met
                          ? 'text-green-600 dark:text-green-400'
                          : 'text-gray-400 dark:text-gray-500'
                      }`}
                    >
                      {check.met ? (
                        <Check className="h-3 w-3" aria-hidden="true" />
                      ) : (
                        <X className="h-3 w-3" aria-hidden="true" />
                      )}
                      {check.label}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>

          <div>
            <label
              htmlFor="confirm-password"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
            >
              Confirm password
            </label>
            <input
              id="confirm-password"
              type={showPassword ? 'text' : 'password'}
              autoComplete="new-password"
              required
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className={`block w-full rounded-lg border bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:outline-none transition-colors ${
                passwordsMismatch
                  ? 'border-red-300 dark:border-red-700 focus:border-red-500 focus:ring-red-500/20'
                  : passwordsMatch
                    ? 'border-green-300 dark:border-green-700 focus:border-green-500 focus:ring-green-500/20'
                    : 'border-gray-300 dark:border-gray-700 focus:border-brand-500 focus:ring-brand-500/20'
              }`}
              placeholder="Confirm your password"
              aria-required="true"
            />
            {passwordsMismatch && (
              <p className="mt-1 text-xs text-red-600 dark:text-red-400">
                Passwords do not match
              </p>
            )}
          </div>

          {(showInvite || requiresInvite) && (
            <div>
              <label
                htmlFor="invite-token"
                className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
              >
                Invite token{requiresInvite && ' (required)'}
              </label>
              <input
                id="invite-token"
                type="text"
                value={inviteToken}
                onChange={(e) => setInviteToken(e.target.value)}
                required={requiresInvite}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                placeholder="Enter your invite token"
                aria-required={requiresInvite}
              />
            </div>
          )}

          {!showInvite && !requiresInvite && (
            <button
              type="button"
              onClick={() => setShowInvite(true)}
              className="text-xs text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 transition-colors"
            >
              Have an invite token?
            </button>
          )}

          <div className="flex items-start gap-2.5 pt-1">
            <input
              id="terms"
              type="checkbox"
              checked={acceptTerms}
              onChange={(e) => setAcceptTerms(e.target.checked)}
              className="mt-0.5 h-4 w-4 rounded border-gray-300 dark:border-gray-700 text-brand-600 focus:ring-brand-500"
              aria-required="true"
            />
            <label
              htmlFor="terms"
              className="text-sm text-gray-600 dark:text-gray-400 leading-relaxed"
            >
              I agree to the{' '}
              <Link
                href="/about"
                className="text-brand-600 dark:text-brand-400 hover:underline"
              >
                terms of service
              </Link>{' '}
              and community guidelines
            </label>
          </div>

          <button
            type="submit"
            disabled={isSubmitting || !canSubmit}
            className="w-full rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
          >
            {isSubmitting ? (
              <span className="inline-flex items-center gap-2">
                <LoadingSpinner />
                Creating account...
              </span>
            ) : (
              'Create account'
            )}
          </button>
        </form>

        <p className="mt-8 text-center text-sm text-gray-600 dark:text-gray-400">
          Already have an account?{' '}
          <Link
            href="/auth/login"
            className="font-medium text-brand-600 dark:text-brand-400 hover:underline"
          >
            Sign in
          </Link>
        </p>
      </div>
    </div>
  );
}
