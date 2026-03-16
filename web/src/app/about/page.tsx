import { Metadata } from 'next';
import { api } from '@/lib/api';
import { Nav } from '@/components/Nav';
import {
  Users,
  MessageSquare,
  Activity,
  Shield,
  Mail,
  Server,
  Puzzle,
} from 'lucide-react';

interface InstanceAbout {
  title: string;
  description: string;
  description_html?: string;
  rules: Array<{ id: string; text: string }>;
  admin?: {
    handle: string;
    display_name: string;
    avatar_url: string;
    email?: string;
  };
  stats: {
    user_count: number;
    post_count: number;
    monthly_active_users: number;
  };
  version: string;
  source_url?: string;
  extensions: string[];
  registrations: boolean;
  approval_required: boolean;
}

async function getAbout(): Promise<InstanceAbout> {
  try {
    return await api.getAbout();
  } catch {
    return {
      title: 'Sojorn',
      description: 'A federated social network built for real conversations.',
      rules: [],
      stats: { user_count: 0, post_count: 0, monthly_active_users: 0 },
      version: 'unknown',
      extensions: [],
      registrations: true,
      approval_required: false,
    };
  }
}

export async function generateMetadata(): Promise<Metadata> {
  const about = await getAbout();
  return {
    title: `About ${about.title}`,
    description: about.description,
    openGraph: {
      title: `About ${about.title}`,
      description: about.description,
    },
  };
}

export default async function AboutPage() {
  const about = await getAbout();

  const statItems = [
    {
      icon: Users,
      label: 'Users',
      value: about.stats.user_count.toLocaleString(),
    },
    {
      icon: MessageSquare,
      label: 'Posts',
      value: about.stats.post_count.toLocaleString(),
    },
    {
      icon: Activity,
      label: 'Monthly active',
      value: about.stats.monthly_active_users.toLocaleString(),
    },
  ];

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Nav />
      <main className="mx-auto max-w-3xl px-4 py-8 sm:py-12">
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-3xl sm:text-4xl font-bold text-gray-900 dark:text-gray-50">
            About {about.title}
          </h1>
          {about.description_html ? (
            <div
              className="mt-4 text-lg text-gray-600 dark:text-gray-400 leading-relaxed max-w-2xl mx-auto prose dark:prose-invert"
              dangerouslySetInnerHTML={{ __html: about.description_html }}
            />
          ) : (
            <p className="mt-4 text-lg text-gray-600 dark:text-gray-400 leading-relaxed max-w-2xl mx-auto">
              {about.description}
            </p>
          )}
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-4 mb-12">
          {statItems.map((stat) => (
            <div
              key={stat.label}
              className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4 sm:p-6 text-center"
            >
              <stat.icon
                className="h-6 w-6 text-brand-500 mx-auto mb-2"
                aria-hidden="true"
              />
              <p className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-gray-50">
                {stat.value}
              </p>
              <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {stat.label}
              </p>
            </div>
          ))}
        </div>

        {/* Rules */}
        {about.rules.length > 0 && (
          <section className="mb-12" aria-label="Instance rules">
            <div className="flex items-center gap-2 mb-4">
              <Shield
                className="h-5 w-5 text-brand-500"
                aria-hidden="true"
              />
              <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-50">
                Rules
              </h2>
            </div>
            <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 divide-y divide-gray-100 dark:divide-gray-800">
              {about.rules.map((rule, index) => (
                <div key={rule.id} className="flex gap-4 p-4">
                  <span className="flex h-7 w-7 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/40 text-sm font-semibold text-brand-700 dark:text-brand-300 flex-shrink-0">
                    {index + 1}
                  </span>
                  <p className="text-sm text-gray-700 dark:text-gray-300 leading-relaxed pt-0.5">
                    {rule.text}
                  </p>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Admin */}
        {about.admin && (
          <section className="mb-12" aria-label="Administration">
            <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-50 mb-4">
              Administered by
            </h2>
            <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4 flex items-center gap-4">
              <div className="relative h-12 w-12 rounded-full overflow-hidden bg-gray-200 dark:bg-gray-800 flex-shrink-0">
                {about.admin.avatar_url ? (
                  <img
                    src={about.admin.avatar_url}
                    alt={`${about.admin.display_name}'s avatar`}
                    className="h-full w-full object-cover"
                  />
                ) : (
                  <span className="flex h-full w-full items-center justify-center text-lg font-bold text-gray-400">
                    {(about.admin.display_name || about.admin.handle)[0]?.toUpperCase()}
                  </span>
                )}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-gray-900 dark:text-gray-50 truncate">
                  {about.admin.display_name}
                </p>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  @{about.admin.handle}
                </p>
              </div>
              {about.admin.email && (
                <a
                  href={`mailto:${about.admin.email}`}
                  className="inline-flex items-center gap-1.5 rounded-lg border border-gray-300 dark:border-gray-700 px-3 py-1.5 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                  aria-label={`Email ${about.admin.display_name}`}
                >
                  <Mail className="h-4 w-4" aria-hidden="true" />
                  Contact
                </a>
              )}
            </div>
          </section>
        )}

        {/* Extensions */}
        {about.extensions.length > 0 && (
          <section className="mb-12" aria-label="Enabled extensions">
            <div className="flex items-center gap-2 mb-4">
              <Puzzle
                className="h-5 w-5 text-brand-500"
                aria-hidden="true"
              />
              <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-50">
                Extensions
              </h2>
            </div>
            <div className="flex flex-wrap gap-2">
              {about.extensions.map((ext) => (
                <span
                  key={ext}
                  className="inline-flex items-center rounded-full bg-brand-50 dark:bg-brand-900/30 border border-brand-200 dark:border-brand-800 px-3 py-1 text-sm font-medium text-brand-700 dark:text-brand-300"
                >
                  {ext}
                </span>
              ))}
            </div>
          </section>
        )}

        {/* Version / Server info */}
        <section aria-label="Server information">
          <div className="flex items-center gap-2 mb-4">
            <Server
              className="h-5 w-5 text-brand-500"
              aria-hidden="true"
            />
            <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-50">
              Server
            </h2>
          </div>
          <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
            <dl className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
              <div>
                <dt className="text-gray-500 dark:text-gray-400">Software</dt>
                <dd className="font-medium text-gray-900 dark:text-gray-100">
                  Sojorn
                </dd>
              </div>
              <div>
                <dt className="text-gray-500 dark:text-gray-400">Version</dt>
                <dd className="font-medium text-gray-900 dark:text-gray-100">
                  {about.version}
                </dd>
              </div>
              <div>
                <dt className="text-gray-500 dark:text-gray-400">
                  Registrations
                </dt>
                <dd className="font-medium text-gray-900 dark:text-gray-100">
                  {about.registrations
                    ? about.approval_required
                      ? 'Open (approval required)'
                      : 'Open'
                    : 'Closed'}
                </dd>
              </div>
              {about.source_url && (
                <div>
                  <dt className="text-gray-500 dark:text-gray-400">
                    Source code
                  </dt>
                  <dd>
                    <a
                      href={about.source_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="font-medium text-brand-600 dark:text-brand-400 hover:underline"
                    >
                      View on GitHub
                    </a>
                  </dd>
                </div>
              )}
            </dl>
          </div>
        </section>
      </main>
    </div>
  );
}
