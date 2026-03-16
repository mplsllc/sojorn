import Link from 'next/link';
import { Home, Search, ArrowLeft } from 'lucide-react';

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gray-50 dark:bg-gray-950 px-4">
      <div className="text-center max-w-md">
        <p className="text-7xl font-extrabold text-brand-600 dark:text-brand-400">
          404
        </p>
        <h1 className="mt-4 text-2xl font-bold text-gray-900 dark:text-gray-50">
          Page not found
        </h1>
        <p className="mt-3 text-gray-600 dark:text-gray-400 leading-relaxed">
          The page you are looking for does not exist, has been moved, or the
          link may be broken.
        </p>
        <div className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-3">
          <Link
            href="/"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-lg bg-brand-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
          >
            <Home className="h-4 w-4" aria-hidden="true" />
            Go home
          </Link>
          <Link
            href="/discover"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-5 py-2.5 text-sm font-semibold text-gray-900 dark:text-gray-100 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
          >
            <Search className="h-4 w-4" aria-hidden="true" />
            Discover
          </Link>
        </div>
      </div>
    </div>
  );
}
