// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useState } from 'react';
import { Send, CheckCircle, AlertCircle, Bell } from 'lucide-react';

type PushResult =
  | { sent: true; token_count: number }
  | { sent: false; reason: string };

export default function NotificationsPage() {
  const [userId, setUserId] = useState('');
  const [title, setTitle] = useState('Test Notification');
  const [body, setBody] = useState('This is a test push from Sojorn Admin.');
  const [sending, setSending] = useState(false);
  const [result, setResult] = useState<PushResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const send = async () => {
    if (!userId.trim()) return;
    setSending(true);
    setResult(null);
    setError(null);
    try {
      const res = await api.sendTestPush({ user_id: userId.trim(), title, body });
      setResult(res as PushResult);
    } catch (e: any) {
      setError(e.message ?? 'Request failed');
    } finally {
      setSending(false);
    }
  };

  return (
    <AdminOnlyGuard>
      <AdminShell>
        <div className="mb-6">
          <h1 className="text-2xl font-bold text-gray-900">Notifications</h1>
          <p className="text-sm text-gray-500 mt-1">
            Send a test push notification to any user to verify FCM delivery and deep-link behavior.
          </p>
        </div>

        {/* Test push form */}
        <div className="bg-white border rounded-xl p-6 mb-6 max-w-xl">
          <h2 className="text-sm font-semibold text-gray-700 mb-4 flex items-center gap-2">
            <Bell className="w-4 h-4" /> Send Test Push
          </h2>

          <div className="space-y-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">User ID (UUID)</label>
              <input
                type="text"
                value={userId}
                onChange={(e) => setUserId(e.target.value)}
                placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                className="w-full border rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-brand-400"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Title</label>
              <input
                type="text"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-400"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Body</label>
              <textarea
                value={body}
                onChange={(e) => setBody(e.target.value)}
                rows={2}
                className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-400 resize-none"
              />
            </div>

            <button
              onClick={send}
              disabled={sending || !userId.trim()}
              className="flex items-center gap-2 px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Send className="w-4 h-4" />
              {sending ? 'Sending…' : 'Send Push'}
            </button>
          </div>

          {/* Result */}
          {result && (
            <div className={`mt-4 p-3 rounded-lg flex items-start gap-2 text-sm ${
              result.sent
                ? 'bg-green-50 border border-green-200 text-green-800'
                : 'bg-amber-50 border border-amber-200 text-amber-800'
            }`}>
              {result.sent
                ? <CheckCircle className="w-4 h-4 mt-0.5 flex-shrink-0" />
                : <AlertCircle className="w-4 h-4 mt-0.5 flex-shrink-0" />}
              <div>
                {result.sent
                  ? <>Sent to <strong>{result.token_count}</strong> device{result.token_count !== 1 ? 's' : ''}.</>
                  : <>Not sent: <strong>{result.reason}</strong></>}
              </div>
            </div>
          )}

          {error && (
            <div className="mt-4 p-3 rounded-lg bg-red-50 border border-red-200 text-red-800 text-sm flex items-start gap-2">
              <AlertCircle className="w-4 h-4 mt-0.5 flex-shrink-0" />
              {error}
            </div>
          )}
        </div>

        {/* Terminated-state test protocol */}
        <div className="bg-white border rounded-xl p-6 max-w-xl">
          <h2 className="text-sm font-semibold text-gray-700 mb-3">Terminated-State Test Protocol</h2>
          <p className="text-xs text-gray-500 mb-4">
            This test verifies push delivery and deep-link behavior when the app is fully closed —
            the scenario most likely to fail silently due to battery optimization.
          </p>
          <ol className="space-y-2 text-sm text-gray-700">
            {[
              'Install the app on a physical Android or iOS device.',
              'Sign in as a test user and note the user ID from your database.',
              'Fully close the app (swipe away from the app switcher).',
              'Wait at least 10 minutes — this triggers Android battery optimization.',
              'Paste the user ID above and click Send Push.',
              'Verify the notification arrives on the device.',
              'Tap the notification — verify it opens the correct screen (not just the home feed).',
              'Repeat on iOS if both platforms are in scope.',
            ].map((step, i) => (
              <li key={i} className="flex gap-3">
                <span className="flex-shrink-0 w-5 h-5 rounded-full bg-brand-100 text-brand-700 text-xs flex items-center justify-center font-semibold">
                  {i + 1}
                </span>
                {step}
              </li>
            ))}
          </ol>
          <div className="mt-4 p-3 bg-amber-50 border border-amber-100 rounded-lg text-xs text-amber-700">
            If the notification does not arrive within 2 minutes, check that the device is not in
            airplane mode, that the app has notification permission, and that the FCM token is
            registered (no_tokens_found response above means the user hasn&apos;t opened the app since
            install or after logout).
          </div>
        </div>
      </AdminShell>
    </AdminOnlyGuard>
  );
}
