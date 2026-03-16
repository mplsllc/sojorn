'use client';

import { useState, useCallback, useRef, useEffect, type FormEvent, type KeyboardEvent } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import {
  Search,
  Bell,
  Menu,
  X,
  User,
  Settings,
  LogOut,
  ChevronDown,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Avatar } from '@/components/Avatar';

export interface NavUser {
  id: string;
  display_name: string;
  handle: string;
  avatar_url?: string | null;
}

export interface NavProps {
  user?: NavUser | null;
  unreadNotifications?: number;
  onLogout?: () => void;
}

export function Nav({ user, unreadNotifications = 0, onLogout }: NavProps) {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [dropdownOpen, setDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  const handleSearch = useCallback(
    (e: FormEvent) => {
      e.preventDefault();
      const q = query.trim();
      if (!q) return;
      router.push(`/discover?q=${encodeURIComponent(q)}`);
      setMobileMenuOpen(false);
    },
    [query, router],
  );

  const handleDropdownKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape') setDropdownOpen(false);
    },
    [],
  );

  return (
    <header
      className="sticky top-0 z-50 w-full border-b border-gray-200 bg-white/80 backdrop-blur-md dark:border-gray-800 dark:bg-gray-950/80"
      role="banner"
    >
      <div className="mx-auto flex h-14 max-w-5xl items-center gap-4 px-4">
        {/* Logo */}
        <Link
          href="/feed"
          className="shrink-0 text-xl font-bold text-indigo-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 rounded dark:text-indigo-400"
        >
          Sojorn
        </Link>

        {/* Search — desktop */}
        <form
          onSubmit={handleSearch}
          className="hidden flex-1 sm:flex sm:max-w-md mx-auto"
          role="search"
        >
          <div className="relative w-full">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search..."
              aria-label="Search Sojorn"
              className="h-9 w-full rounded-full border border-gray-200 bg-gray-50 pl-9 pr-4 text-sm text-gray-900 placeholder:text-gray-400 focus:border-indigo-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/30 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 dark:placeholder:text-gray-500"
            />
          </div>
        </form>

        {/* Right side actions */}
        <div className="ml-auto flex items-center gap-2">
          {/* Notifications */}
          {user && (
            <Link
              href="/notifications"
              className="relative rounded-full p-2 text-gray-600 hover:bg-gray-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 dark:text-gray-300 dark:hover:bg-gray-800"
              aria-label={`Notifications${unreadNotifications > 0 ? `, ${unreadNotifications} unread` : ''}`}
            >
              <Bell className="h-5 w-5" />
              {unreadNotifications > 0 && (
                <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold text-white">
                  {unreadNotifications > 99 ? '99+' : unreadNotifications}
                </span>
              )}
            </Link>
          )}

          {/* User dropdown — desktop */}
          {user ? (
            <div ref={dropdownRef} className="relative hidden sm:block" onKeyDown={handleDropdownKeyDown}>
              <button
                onClick={() => setDropdownOpen((o) => !o)}
                className="flex items-center gap-1.5 rounded-full p-1 hover:bg-gray-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 dark:hover:bg-gray-800"
                aria-expanded={dropdownOpen}
                aria-haspopup="true"
                aria-label="User menu"
              >
                <Avatar src={user.avatar_url} alt={user.display_name} size="sm" />
                <ChevronDown className={cn('h-4 w-4 text-gray-500 transition-transform', dropdownOpen && 'rotate-180')} />
              </button>

              {dropdownOpen && (
                <div
                  className="absolute right-0 mt-2 w-56 origin-top-right rounded-lg border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-700 dark:bg-gray-900"
                  role="menu"
                >
                  <div className="border-b border-gray-100 px-4 py-2 dark:border-gray-800">
                    <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                      {user.display_name}
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400">@{user.handle}</p>
                  </div>

                  <Link
                    href={`/profile/${user.handle}`}
                    className="flex items-center gap-2 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-800"
                    role="menuitem"
                    onClick={() => setDropdownOpen(false)}
                  >
                    <User className="h-4 w-4" /> Profile
                  </Link>
                  <Link
                    href="/settings"
                    className="flex items-center gap-2 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-800"
                    role="menuitem"
                    onClick={() => setDropdownOpen(false)}
                  >
                    <Settings className="h-4 w-4" /> Settings
                  </Link>
                  <button
                    className="flex w-full items-center gap-2 px-4 py-2 text-sm text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950"
                    role="menuitem"
                    onClick={() => {
                      setDropdownOpen(false);
                      onLogout?.();
                    }}
                  >
                    <LogOut className="h-4 w-4" /> Log out
                  </button>
                </div>
              )}
            </div>
          ) : (
            <Link
              href="/auth/login"
              className="hidden rounded-lg bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-indigo-700 sm:inline-flex focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 dark:bg-indigo-500"
            >
              Sign in
            </Link>
          )}

          {/* Hamburger — mobile */}
          <button
            className="rounded-full p-2 text-gray-600 hover:bg-gray-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 sm:hidden dark:text-gray-300 dark:hover:bg-gray-800"
            onClick={() => setMobileMenuOpen((o) => !o)}
            aria-expanded={mobileMenuOpen}
            aria-label={mobileMenuOpen ? 'Close menu' : 'Open menu'}
          >
            {mobileMenuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </div>

      {/* Mobile menu */}
      {mobileMenuOpen && (
        <nav className="border-t border-gray-200 px-4 pb-4 pt-3 sm:hidden dark:border-gray-800" aria-label="Mobile navigation">
          <form onSubmit={handleSearch} className="mb-3" role="search">
            <div className="relative">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <input
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search..."
                aria-label="Search Sojorn"
                className="h-9 w-full rounded-full border border-gray-200 bg-gray-50 pl-9 pr-4 text-sm text-gray-900 placeholder:text-gray-400 focus:border-indigo-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/30 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 dark:placeholder:text-gray-500"
              />
            </div>
          </form>

          {user ? (
            <div className="space-y-1">
              <Link
                href={`/profile/${user.handle}`}
                className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800"
                onClick={() => setMobileMenuOpen(false)}
              >
                <User className="h-4 w-4" /> Profile
              </Link>
              <Link
                href="/settings"
                className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800"
                onClick={() => setMobileMenuOpen(false)}
              >
                <Settings className="h-4 w-4" /> Settings
              </Link>
              <button
                className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950"
                onClick={() => {
                  setMobileMenuOpen(false);
                  onLogout?.();
                }}
              >
                <LogOut className="h-4 w-4" /> Log out
              </button>
            </div>
          ) : (
            <Link
              href="/auth/login"
              className="block rounded-lg bg-indigo-600 px-4 py-2 text-center text-sm font-medium text-white hover:bg-indigo-700 dark:bg-indigo-500"
              onClick={() => setMobileMenuOpen(false)}
            >
              Sign in
            </Link>
          )}
        </nav>
      )}
    </header>
  );
}
