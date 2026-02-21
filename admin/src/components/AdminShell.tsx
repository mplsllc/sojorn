// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { useAuth } from '@/lib/auth';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import Sidebar from './Sidebar';

export default function AdminShell({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      router.push('/login');
    }
  }, [isAuthenticated, isLoading, router]);

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-warm-100">
        <div className="animate-pulse flex flex-col items-center gap-3">
          <div className="w-10 h-10 bg-brand-500 rounded-lg" />
          <p className="text-sm text-gray-400">Loading...</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) return null;

  return (
    <div className="min-h-screen bg-warm-100">
      <Sidebar />
      <main className="ml-60 min-h-screen">
        <div className="p-6">{children}</div>
      </main>
    </div>
  );
}
