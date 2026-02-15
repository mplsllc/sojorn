'use client';

import AdminShell from '@/components/AdminShell';
import { useState } from 'react';
import { Settings, Globe, Key } from 'lucide-react';

export default function SettingsPage() {
  const [apiUrl, setApiUrl] = useState(
    typeof window !== 'undefined' ? localStorage.getItem('admin_api_url') || '' : ''
  );
  const [saved, setSaved] = useState(false);

  const handleSaveApiUrl = () => {
    if (typeof window !== 'undefined') {
      if (apiUrl.trim()) {
        localStorage.setItem('admin_api_url', apiUrl.trim());
      } else {
        localStorage.removeItem('admin_api_url');
      }
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    }
  };

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
        <p className="text-sm text-gray-500 mt-1">Admin panel configuration</p>
      </div>

      <div className="space-y-6 max-w-2xl">
        {/* API Configuration */}
        <div className="card p-5">
          <div className="flex items-center gap-2 mb-4">
            <Globe className="w-5 h-5 text-brand-500" />
            <h3 className="text-lg font-semibold text-gray-900">API Connection</h3>
          </div>
          <div className="space-y-3">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">API Base URL</label>
              <input
                className="input"
                placeholder="https://api.sojorn.net (default)"
                value={apiUrl}
                onChange={(e) => setApiUrl(e.target.value)}
              />
              <p className="text-xs text-gray-400 mt-1">
                Override the default API URL. Leave blank to use the default from environment variables.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <button onClick={handleSaveApiUrl} className="btn-primary text-sm">
                Save
              </button>
              {saved && <span className="text-sm text-green-600">Saved!</span>}
            </div>
          </div>
        </div>

        {/* Session Info */}
        <div className="card p-5">
          <div className="flex items-center gap-2 mb-4">
            <Key className="w-5 h-5 text-brand-500" />
            <h3 className="text-lg font-semibold text-gray-900">Session</h3>
          </div>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-500">Token stored</span>
              <span className="text-gray-900 font-medium">
                {typeof window !== 'undefined' && localStorage.getItem('admin_token') ? 'Yes' : 'No'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-500">API URL</span>
              <span className="text-gray-900 font-medium font-mono text-xs">
                {process.env.NEXT_PUBLIC_API_URL || 'https://api.sojorn.net'}
              </span>
            </div>
          </div>
        </div>

        {/* About */}
        <div className="card p-5">
          <div className="flex items-center gap-2 mb-4">
            <Settings className="w-5 h-5 text-brand-500" />
            <h3 className="text-lg font-semibold text-gray-900">About</h3>
          </div>
          <div className="space-y-2 text-sm text-gray-500">
            <p><strong className="text-gray-700">Sojorn Admin Panel</strong> v1.0.0</p>
            <p>Built with Next.js, React, TypeScript, and TailwindCSS</p>
            <p>Backend: Go (Gin) + PostgreSQL</p>
          </div>
        </div>
      </div>
    </AdminShell>
  );
}
