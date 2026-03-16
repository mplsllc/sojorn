import { Metadata } from 'next';
import { api } from '@/lib/api';
import Link from 'next/link';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import {
  Globe,
  Shield,
  Puzzle,
  MessageCircle,
  Users,
  Zap,
} from 'lucide-react';

interface InstanceInfo {
  title: string;
  description: string;
  stats?: {
    user_count: number;
    post_count: number;
    monthly_active_users: number;
  };
  registrations: boolean;
  approval_required: boolean;
  extensions?: string[];
}

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

async function checkSetupStatus(): Promise<boolean> {
  try {
    const res = await fetch(`${API_BASE}/api/v1/setup/status`, { cache: 'no-store' });
    const data = await res.json();
    return data.configured === true;
  } catch {
    // If the API is unreachable, assume configured to avoid redirect loops
    return true;
  }
}

async function getInstance(): Promise<InstanceInfo> {
  try {
    return await api.getInstance();
  } catch {
    return {
      title: 'Sojorn',
      description: 'A federated social network built for real conversations.',
      registrations: true,
      approval_required: false,
    };
  }
}

export async function generateMetadata(): Promise<Metadata> {
  const instance = await getInstance();
  return {
    title: instance.title,
    description: instance.description,
    openGraph: {
      title: instance.title,
      description: instance.description,
    },
  };
}

const features = [
  {
    icon: Globe,
    title: 'Federated',
    description:
      'Connect with people across the fediverse. Your identity, your server, your rules.',
  },
  {
    icon: Shield,
    title: 'Privacy-first',
    description:
      'Granular visibility controls on every post. Share with the world or just your circle.',
  },
  {
    icon: Puzzle,
    title: 'Extensible',
    description:
      'Powerful extension system lets instances add custom features and integrations.',
  },
  {
    icon: MessageCircle,
    title: 'Rich conversations',
    description:
      'Threaded replies, reactions, polls, and long-form content. Express yourself fully.',
  },
  {
    icon: Users,
    title: 'Community-driven',
    description:
      'Moderation tools built for communities. Admins and mods keep spaces healthy.',
  },
  {
    icon: Zap,
    title: 'Fast & lightweight',
    description:
      'Built with performance in mind. Instant loading, real-time updates, offline support.',
  },
];

export default async function LandingPage() {
  // If no admin has been created yet, redirect to the first-run setup wizard
  const configured = await checkSetupStatus();
  if (!configured) {
    redirect('/setup');
  }

  const cookieStore = cookies();
  const token = cookieStore.get('token')?.value;
  if (token) {
    redirect('/feed');
  }

  const instance = await getInstance();

  return (
    <div className="min-h-screen bg-gradient-to-b from-brand-50 via-white to-white dark:from-brand-950/30 dark:via-gray-950 dark:to-gray-950">
      {/* Header */}
      <header className="border-b border-gray-200/60 dark:border-gray-800/60 backdrop-blur-sm bg-white/70 dark:bg-gray-950/70 sticky top-0 z-50">
        <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8 flex items-center justify-between h-16">
          <Link
            href="/"
            className="text-xl font-bold text-brand-600 dark:text-brand-400"
            aria-label="Sojorn home"
          >
            {instance.title}
          </Link>
          <nav className="flex items-center gap-3" aria-label="Primary">
            <Link
              href="/about"
              className="text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 transition-colors px-3 py-2"
            >
              About
            </Link>
            <Link
              href="/discover"
              className="text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 transition-colors px-3 py-2"
            >
              Explore
            </Link>
            <Link
              href="/auth/login"
              className="text-sm font-medium text-brand-600 hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300 transition-colors px-3 py-2"
            >
              Log in
            </Link>
            {instance.registrations && (
              <Link
                href="/auth/register"
                className="text-sm font-medium bg-brand-600 hover:bg-brand-700 text-white rounded-lg px-4 py-2 transition-colors"
              >
                Join
              </Link>
            )}
          </nav>
        </div>
      </header>

      {/* Hero */}
      <main>
        <section className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 pt-20 pb-16 sm:pt-32 sm:pb-24 text-center">
          <h1 className="text-4xl sm:text-6xl font-extrabold tracking-tight text-gray-900 dark:text-gray-50">
            Social networking,{' '}
            <span className="text-brand-600 dark:text-brand-400">
              reimagined
            </span>
          </h1>
          <p className="mt-6 text-lg sm:text-xl text-gray-600 dark:text-gray-400 max-w-2xl mx-auto leading-relaxed">
            {instance.description}
          </p>
          <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4">
            {instance.registrations && (
              <Link
                href="/auth/register"
                className="w-full sm:w-auto inline-flex items-center justify-center rounded-xl bg-brand-600 px-8 py-3.5 text-base font-semibold text-white shadow-lg shadow-brand-500/25 hover:bg-brand-700 transition-all hover:shadow-brand-500/40 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
              >
                Create an account
              </Link>
            )}
            <Link
              href="/auth/login"
              className="w-full sm:w-auto inline-flex items-center justify-center rounded-xl border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-8 py-3.5 text-base font-semibold text-gray-900 dark:text-gray-100 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
            >
              Log in
            </Link>
          </div>

          {instance.stats && (
            <div className="mt-16 grid grid-cols-3 gap-8 max-w-md mx-auto">
              <div>
                <p className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-gray-50">
                  {instance.stats.user_count.toLocaleString()}
                </p>
                <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Users
                </p>
              </div>
              <div>
                <p className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-gray-50">
                  {instance.stats.post_count.toLocaleString()}
                </p>
                <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Posts
                </p>
              </div>
              <div>
                <p className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-gray-50">
                  {instance.stats.monthly_active_users.toLocaleString()}
                </p>
                <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Active monthly
                </p>
              </div>
            </div>
          )}
        </section>

        {/* Features */}
        <section className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8 pb-24">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-8">
            {features.map((feature) => (
              <div
                key={feature.title}
                className="rounded-2xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6 hover:shadow-lg transition-shadow"
              >
                <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-brand-100 dark:bg-brand-900/40">
                  <feature.icon
                    className="h-6 w-6 text-brand-600 dark:text-brand-400"
                    aria-hidden="true"
                  />
                </div>
                <h3 className="mt-4 text-lg font-semibold text-gray-900 dark:text-gray-50">
                  {feature.title}
                </h3>
                <p className="mt-2 text-sm leading-relaxed text-gray-600 dark:text-gray-400">
                  {feature.description}
                </p>
              </div>
            ))}
          </div>
        </section>

        {/* Extensions */}
        {instance.extensions && instance.extensions.length > 0 && (
          <section className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 pb-24 text-center">
            <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-50">
              Powered by extensions
            </h2>
            <p className="mt-3 text-gray-600 dark:text-gray-400">
              This instance has the following extensions enabled:
            </p>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              {instance.extensions.map((ext) => (
                <span
                  key={ext}
                  className="inline-flex items-center rounded-full bg-brand-50 dark:bg-brand-900/30 border border-brand-200 dark:border-brand-800 px-4 py-1.5 text-sm font-medium text-brand-700 dark:text-brand-300"
                >
                  {ext}
                </span>
              ))}
            </div>
          </section>
        )}

        {/* CTA */}
        <section className="bg-brand-600 dark:bg-brand-900">
          <div className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-16 sm:py-24 text-center">
            <h2 className="text-3xl font-bold text-white">
              Ready to join the conversation?
            </h2>
            <p className="mt-4 text-brand-100 text-lg">
              Take control of your social media experience.
            </p>
            <div className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-4">
              {instance.registrations && (
                <Link
                  href="/auth/register"
                  className="w-full sm:w-auto inline-flex items-center justify-center rounded-xl bg-white px-8 py-3.5 text-base font-semibold text-brand-700 hover:bg-brand-50 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
                >
                  Get started
                </Link>
              )}
              <Link
                href="/about"
                className="w-full sm:w-auto inline-flex items-center justify-center rounded-xl border border-brand-400 px-8 py-3.5 text-base font-semibold text-white hover:bg-brand-500 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
              >
                Learn more
              </Link>
            </div>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-950">
        <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8 py-8 flex flex-col sm:flex-row items-center justify-between gap-4">
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Powered by{' '}
            <a
              href="https://sojorn.social"
              className="font-medium text-brand-600 dark:text-brand-400 hover:underline"
              target="_blank"
              rel="noopener noreferrer"
            >
              Sojorn
            </a>
          </p>
          <nav className="flex items-center gap-6" aria-label="Footer">
            <Link
              href="/about"
              className="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300 transition-colors"
            >
              About
            </Link>
            <Link
              href="/discover"
              className="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300 transition-colors"
            >
              Discover
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  );
}
