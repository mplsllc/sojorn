// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

import type { Metadata } from 'next';
import './globals.css';
import { AuthProvider } from '@/lib/auth';

export const metadata: Metadata = {
  title: 'Sojorn Admin',
  description: 'Sojorn Social Network Administration Panel',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
