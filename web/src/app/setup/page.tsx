'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { setTokens } from '@/lib/api';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface FormData {
  handle: string;
  email: string;
  password: string;
  confirmPassword: string;
  instanceName: string;
  instanceDescription: string;
  registrationMode: 'open' | 'invite' | 'closed';
}

const INITIAL: FormData = {
  handle: '',
  email: '',
  password: '',
  confirmPassword: '',
  instanceName: '',
  instanceDescription: '',
  registrationMode: 'invite',
};

// ---------------------------------------------------------------------------
// Password strength
// ---------------------------------------------------------------------------

function passwordStrength(pw: string): { score: number; label: string; color: string } {
  let score = 0;
  if (pw.length >= 8) score++;
  if (pw.length >= 12) score++;
  if (/[A-Z]/.test(pw)) score++;
  if (/[0-9]/.test(pw)) score++;
  if (/[^A-Za-z0-9]/.test(pw)) score++;

  if (score <= 1) return { score, label: 'Weak', color: 'bg-red-500' };
  if (score <= 2) return { score, label: 'Fair', color: 'bg-orange-500' };
  if (score <= 3) return { score, label: 'Good', color: 'bg-yellow-500' };
  return { score, label: 'Strong', color: 'bg-green-500' };
}

// ---------------------------------------------------------------------------
// Step indicator
// ---------------------------------------------------------------------------

function StepIndicator({ current, total }: { current: number; total: number }) {
  return (
    <div className="flex items-center justify-center gap-2 mb-10">
      {Array.from({ length: total }, (_, i) => {
        const step = i + 1;
        const isActive = step === current;
        const isDone = step < current;
        return (
          <div key={step} className="flex items-center gap-2">
            <div
              className={`
                flex h-9 w-9 items-center justify-center rounded-full text-sm font-semibold transition-all duration-300
                ${isActive ? 'bg-brand-600 text-white scale-110 shadow-lg shadow-brand-500/30' : ''}
                ${isDone ? 'bg-brand-600 text-white' : ''}
                ${!isActive && !isDone ? 'bg-gray-200 dark:bg-gray-700 text-gray-500 dark:text-gray-400' : ''}
              `}
            >
              {isDone ? (
                <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              ) : (
                step
              )}
            </div>
            {step < total && (
              <div
                className={`h-0.5 w-8 transition-colors duration-300 ${
                  isDone ? 'bg-brand-600' : 'bg-gray-200 dark:bg-gray-700'
                }`}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Registration mode cards
// ---------------------------------------------------------------------------

const REG_MODES: { value: FormData['registrationMode']; title: string; desc: string }[] = [
  { value: 'open', title: 'Open', desc: 'Anyone can create an account freely.' },
  { value: 'invite', title: 'Invite only', desc: 'New members need an invite link from an existing member.' },
  { value: 'closed', title: 'Closed', desc: 'Only admins can create accounts. No public registration.' },
];

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export default function SetupWizard() {
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [form, setForm] = useState<FormData>(INITIAL);
  const [errors, setErrors] = useState<Partial<Record<keyof FormData, string>>>({});
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState('');
  const [ready, setReady] = useState(false);

  // Check if instance is already configured
  useEffect(() => {
    (async () => {
      try {
        const res = await fetch(`${API_BASE}/api/v1/setup/status`);
        const data = await res.json();
        if (data.configured) {
          router.replace('/');
          return;
        }
      } catch {
        // If the endpoint is unreachable, show setup anyway
      }
      setReady(true);
    })();
  }, [router]);

  const update = useCallback(
    <K extends keyof FormData>(key: K, value: FormData[K]) => {
      setForm((prev) => ({ ...prev, [key]: value }));
      setErrors((prev) => ({ ...prev, [key]: undefined }));
      setServerError('');
    },
    [],
  );

  // ---------------------------------------------------------------------------
  // Validation per step
  // ---------------------------------------------------------------------------

  function validateStep(s: number): boolean {
    const errs: Partial<Record<keyof FormData, string>> = {};

    if (s === 2) {
      if (!form.handle.trim()) errs.handle = 'Handle is required';
      else if (form.handle.trim().length < 3) errs.handle = 'Handle must be at least 3 characters';
      else if (!/^[a-zA-Z0-9_]+$/.test(form.handle.trim())) errs.handle = 'Handle can only contain letters, numbers, and underscores';

      if (!form.email.trim()) errs.email = 'Email is required';
      else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) errs.email = 'Enter a valid email address';

      if (!form.password) errs.password = 'Password is required';
      else if (form.password.length < 8) errs.password = 'Password must be at least 8 characters';

      if (form.password !== form.confirmPassword) errs.confirmPassword = 'Passwords do not match';
    }

    if (s === 3) {
      if (!form.instanceName.trim()) errs.instanceName = 'Instance name is required';
    }

    setErrors(errs);
    return Object.keys(errs).length === 0;
  }

  function next() {
    if (validateStep(step)) setStep((s) => Math.min(s + 1, 4));
  }

  function back() {
    setStep((s) => Math.max(s - 1, 1));
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  async function submit() {
    if (!validateStep(3)) {
      setStep(3);
      return;
    }

    setSubmitting(true);
    setServerError('');

    try {
      const res = await fetch(`${API_BASE}/api/v1/setup`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          handle: form.handle.trim(),
          email: form.email.trim().toLowerCase(),
          password: form.password,
          instance_name: form.instanceName.trim(),
          instance_description: form.instanceDescription.trim(),
          registration_mode: form.registrationMode,
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        setServerError(data.error || 'Setup failed');
        setSubmitting(false);
        return;
      }

      // Store JWT
      setTokens(data.token);
      setStep(4);
    } catch (err: any) {
      setServerError(err.message || 'Network error');
    } finally {
      setSubmitting(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Render helpers
  // ---------------------------------------------------------------------------

  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50 dark:bg-gray-950">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-brand-600 border-t-transparent" />
      </div>
    );
  }

  const strength = passwordStrength(form.password);

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-brand-50 via-white to-gray-100 dark:from-gray-950 dark:via-gray-900 dark:to-gray-950 p-4">
      <div className="w-full max-w-lg">
        {step < 4 && <StepIndicator current={step} total={4} />}

        <div className="rounded-2xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 shadow-xl p-8 sm:p-10 transition-all duration-300">
          {/* ── Step 1: Welcome ───────────────────────────── */}
          {step === 1 && (
            <div className="text-center">
              <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-brand-100 dark:bg-brand-900/40">
                <svg className="h-8 w-8 text-brand-600 dark:text-brand-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418" />
                </svg>
              </div>
              <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-50">Welcome to Sojorn</h1>
              <p className="mt-3 text-gray-600 dark:text-gray-400 leading-relaxed">
                A federated social network built for real conversations. Let's get your instance up and running.
              </p>
              <button
                onClick={next}
                className="mt-8 w-full rounded-xl bg-brand-600 px-6 py-3.5 text-base font-semibold text-white shadow-lg shadow-brand-500/25 hover:bg-brand-700 transition-all hover:shadow-brand-500/40 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
              >
                Let's set up your instance
              </button>
            </div>
          )}

          {/* ── Step 2: Admin Account ────────────────────── */}
          {step === 2 && (
            <div>
              <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-50">Create admin account</h2>
              <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                This will be the first administrator of your instance.
              </p>

              <div className="mt-6 space-y-4">
                {/* Handle */}
                <div>
                  <label htmlFor="handle" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Handle
                  </label>
                  <div className="mt-1 relative">
                    <span className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-gray-400">@</span>
                    <input
                      id="handle"
                      type="text"
                      value={form.handle}
                      onChange={(e) => update('handle', e.target.value)}
                      className={`block w-full rounded-lg border ${errors.handle ? 'border-red-400' : 'border-gray-300 dark:border-gray-700'} bg-white dark:bg-gray-800 pl-8 pr-3 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-colors`}
                      placeholder="admin"
                    />
                  </div>
                  {errors.handle && <p className="mt-1 text-xs text-red-500">{errors.handle}</p>}
                </div>

                {/* Email */}
                <div>
                  <label htmlFor="email" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Email
                  </label>
                  <input
                    id="email"
                    type="email"
                    value={form.email}
                    onChange={(e) => update('email', e.target.value)}
                    className={`mt-1 block w-full rounded-lg border ${errors.email ? 'border-red-400' : 'border-gray-300 dark:border-gray-700'} bg-white dark:bg-gray-800 px-3 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-colors`}
                    placeholder="admin@example.com"
                  />
                  {errors.email && <p className="mt-1 text-xs text-red-500">{errors.email}</p>}
                </div>

                {/* Password */}
                <div>
                  <label htmlFor="password" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Password
                  </label>
                  <input
                    id="password"
                    type="password"
                    value={form.password}
                    onChange={(e) => update('password', e.target.value)}
                    className={`mt-1 block w-full rounded-lg border ${errors.password ? 'border-red-400' : 'border-gray-300 dark:border-gray-700'} bg-white dark:bg-gray-800 px-3 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-colors`}
                    placeholder="At least 8 characters"
                  />
                  {form.password && (
                    <div className="mt-2 flex items-center gap-2">
                      <div className="flex-1 h-1.5 rounded-full bg-gray-200 dark:bg-gray-700 overflow-hidden">
                        <div
                          className={`h-full rounded-full transition-all duration-300 ${strength.color}`}
                          style={{ width: `${(strength.score / 5) * 100}%` }}
                        />
                      </div>
                      <span className="text-xs text-gray-500 dark:text-gray-400">{strength.label}</span>
                    </div>
                  )}
                  {errors.password && <p className="mt-1 text-xs text-red-500">{errors.password}</p>}
                </div>

                {/* Confirm Password */}
                <div>
                  <label htmlFor="confirmPassword" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Confirm password
                  </label>
                  <input
                    id="confirmPassword"
                    type="password"
                    value={form.confirmPassword}
                    onChange={(e) => update('confirmPassword', e.target.value)}
                    className={`mt-1 block w-full rounded-lg border ${errors.confirmPassword ? 'border-red-400' : 'border-gray-300 dark:border-gray-700'} bg-white dark:bg-gray-800 px-3 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-colors`}
                    placeholder="Repeat your password"
                  />
                  {errors.confirmPassword && <p className="mt-1 text-xs text-red-500">{errors.confirmPassword}</p>}
                </div>
              </div>

              <div className="mt-8 flex gap-3">
                <button
                  onClick={back}
                  className="flex-1 rounded-xl border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors"
                >
                  Back
                </button>
                <button
                  onClick={next}
                  className="flex-1 rounded-xl bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 transition-colors"
                >
                  Next
                </button>
              </div>
            </div>
          )}

          {/* ── Step 3: Instance Identity ────────────────── */}
          {step === 3 && (
            <div>
              <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-50">Instance identity</h2>
              <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                Give your community a name and set who can join.
              </p>

              <div className="mt-6 space-y-4">
                {/* Instance name */}
                <div>
                  <label htmlFor="instanceName" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Instance name
                  </label>
                  <input
                    id="instanceName"
                    type="text"
                    value={form.instanceName}
                    onChange={(e) => update('instanceName', e.target.value)}
                    className={`mt-1 block w-full rounded-lg border ${errors.instanceName ? 'border-red-400' : 'border-gray-300 dark:border-gray-700'} bg-white dark:bg-gray-800 px-3 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-colors`}
                    placeholder="My Community"
                  />
                  {errors.instanceName && <p className="mt-1 text-xs text-red-500">{errors.instanceName}</p>}
                </div>

                {/* Instance description */}
                <div>
                  <label htmlFor="instanceDescription" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Description <span className="text-gray-400">(optional)</span>
                  </label>
                  <textarea
                    id="instanceDescription"
                    value={form.instanceDescription}
                    onChange={(e) => update('instanceDescription', e.target.value)}
                    rows={3}
                    className="mt-1 block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 px-3 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-colors resize-none"
                    placeholder="A brief description of your community..."
                  />
                </div>

                {/* Registration mode */}
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Registration mode
                  </label>
                  <div className="space-y-2">
                    {REG_MODES.map((mode) => (
                      <button
                        key={mode.value}
                        type="button"
                        onClick={() => update('registrationMode', mode.value)}
                        className={`w-full text-left rounded-xl border-2 p-4 transition-all duration-200 ${
                          form.registrationMode === mode.value
                            ? 'border-brand-500 bg-brand-50 dark:bg-brand-900/20 shadow-sm'
                            : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
                        }`}
                      >
                        <div className="flex items-center gap-3">
                          <div
                            className={`h-4 w-4 rounded-full border-2 flex items-center justify-center transition-colors ${
                              form.registrationMode === mode.value
                                ? 'border-brand-600'
                                : 'border-gray-400 dark:border-gray-500'
                            }`}
                          >
                            {form.registrationMode === mode.value && (
                              <div className="h-2 w-2 rounded-full bg-brand-600" />
                            )}
                          </div>
                          <div>
                            <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">{mode.title}</p>
                            <p className="text-xs text-gray-500 dark:text-gray-400">{mode.desc}</p>
                          </div>
                        </div>
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              {serverError && (
                <div className="mt-4 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-3">
                  <p className="text-sm text-red-700 dark:text-red-400">{serverError}</p>
                </div>
              )}

              <div className="mt-8 flex gap-3">
                <button
                  onClick={back}
                  className="flex-1 rounded-xl border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors"
                >
                  Back
                </button>
                <button
                  onClick={submit}
                  disabled={submitting}
                  className="flex-1 rounded-xl bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {submitting ? (
                    <span className="flex items-center justify-center gap-2">
                      <svg className="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                      </svg>
                      Setting up...
                    </span>
                  ) : (
                    'Complete setup'
                  )}
                </button>
              </div>
            </div>
          )}

          {/* ── Step 4: Complete ──────────────────────────── */}
          {step === 4 && (
            <div className="text-center">
              <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-full bg-green-100 dark:bg-green-900/30">
                <svg className="h-8 w-8 text-green-600 dark:text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-50">Your instance is ready!</h2>
              <p className="mt-2 text-gray-600 dark:text-gray-400">
                You're all set. Your Sojorn instance is configured and your admin account is active.
              </p>

              <div className="mt-8 space-y-3">
                <button
                  onClick={() => router.push('/feed')}
                  className="w-full rounded-xl bg-brand-600 px-6 py-3 text-base font-semibold text-white shadow-lg shadow-brand-500/25 hover:bg-brand-700 transition-all hover:shadow-brand-500/40"
                >
                  Go to your feed
                </button>
                <button
                  onClick={() => router.push('/admin')}
                  className="w-full rounded-xl border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 px-6 py-3 text-base font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors"
                >
                  Open admin panel
                </button>
              </div>
            </div>
          )}
        </div>

        {step < 4 && (
          <p className="mt-6 text-center text-xs text-gray-400 dark:text-gray-500">
            Powered by Sojorn &mdash; open-source federated social networking
          </p>
        )}
      </div>
    </div>
  );
}
