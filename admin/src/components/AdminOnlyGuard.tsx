// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { useAuth } from '@/lib/auth';
import { ShieldAlert } from 'lucide-react';

export default function AdminOnlyGuard({ children }: { children: React.ReactNode }) {
  const { user } = useAuth();

  if (user?.role === 'moderator') {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="text-center max-w-md">
          <div className="w-16 h-16 bg-amber-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <ShieldAlert className="w-8 h-8 text-amber-600" />
          </div>
          <h2 className="text-xl font-semibold text-gray-900 mb-2">Access Restricted</h2>
          <p className="text-sm text-gray-500">
            This page is only available to full administrators. Contact your admin if you need access.
          </p>
        </div>
      </div>
    );
  }

  return <>{children}</>;
}
