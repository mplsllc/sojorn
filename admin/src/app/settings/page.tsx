// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { Settings, Globe, Key, Activity, Users, RefreshCw, Palette } from 'lucide-react';

export default function SettingsPage() {
  const [apiUrl, setApiUrl] = useState(
    typeof window !== 'undefined' ? localStorage.getItem('admin_api_url') || '' : ''
  );
  const [saved, setSaved] = useState(false);
  const [health, setHealth] = useState<any>(null);
  const [healthLoading, setHealthLoading] = useState(true);
  const [adminUsers, setAdminUsers] = useState<any[]>([]);
  const [adminLoading, setAdminLoading] = useState(true);
  const [branding, setBranding] = useState<Record<string, string>>({});
  const [brandingSaving, setBrandingSaving] = useState(false);
  const [brandingSaved, setBrandingSaved] = useState(false);

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

  const loadHealth = () => {
    setHealthLoading(true);
    api.getSystemHealth()
      .then(setHealth)
      .catch(() => {})
      .finally(() => setHealthLoading(false));
  };

  useEffect(() => {
    loadHealth();
    api.listUsers({ role: 'admin', limit: 50 })
      .then((d) => {
        const all = d.users ?? [];
        setAdminUsers(all);
      })
      .catch(() => {})
      .finally(() => setAdminLoading(false));
    api.getInstanceConfig()
      .then((cfg: Record<string, string>) => setBranding(cfg))
      .catch(() => {});
  }, []);

  const handleSaveBranding = async () => {
    setBrandingSaving(true);
    try {
      await api.updateInstanceConfig(branding);
      setBrandingSaved(true);
      setTimeout(() => setBrandingSaved(false), 2000);
    } catch (e) {
      console.error('Failed to save branding', e);
    } finally {
      setBrandingSaving(false);
    }
  };

  const updateBranding = (key: string, value: string) => {
    setBranding((prev) => ({ ...prev, [key]: value }));
  };

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
        <p className="text-sm text-gray-500 mt-1">Admin panel configuration and system info</p>
      </div>

      <div className="space-y-6 max-w-3xl">
        {/* Instance Branding */}
        <div className="card p-5">
          <div className="flex items-center gap-2 mb-4">
            <Palette className="w-5 h-5 text-brand-500" />
            <h3 className="text-lg font-semibold text-gray-900">Instance Branding</h3>
          </div>
          <p className="text-sm text-gray-500 mb-4">
            Configure how your instance appears to users and in the app.
          </p>
          <div className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Instance Name</label>
                <input className="input" placeholder="My Social Network" value={branding.instance_name || ''} onChange={(e) => updateBranding('instance_name', e.target.value)} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Registration Mode</label>
                <select className="input" value={branding.registration_mode || 'open'} onChange={(e) => updateBranding('registration_mode', e.target.value)}>
                  <option value="open">Open</option>
                  <option value="invite">Invite Only</option>
                  <option value="closed">Closed</option>
                </select>
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
              <input className="input" placeholder="A community for..." value={branding.instance_description || ''} onChange={(e) => updateBranding('instance_description', e.target.value)} />
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Logo URL</label>
                <input className="input" placeholder="https://cdn.example.com/logo.png" value={branding.instance_logo_url || ''} onChange={(e) => updateBranding('instance_logo_url', e.target.value)} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Accent Color</label>
                <div className="flex gap-2">
                  <input type="color" className="h-10 w-10 rounded border border-warm-300 cursor-pointer" value={branding.instance_accent_color || '#6366f1'} onChange={(e) => updateBranding('instance_accent_color', e.target.value)} />
                  <input className="input flex-1" placeholder="#6366f1" value={branding.instance_accent_color || ''} onChange={(e) => updateBranding('instance_accent_color', e.target.value)} />
                </div>
              </div>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Contact Email</label>
                <input className="input" placeholder="hello@example.com" value={branding.contact_email || ''} onChange={(e) => updateBranding('contact_email', e.target.value)} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Terms URL</label>
                <input className="input" placeholder="/terms" value={branding.terms_url || ''} onChange={(e) => updateBranding('terms_url', e.target.value)} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Privacy URL</label>
                <input className="input" placeholder="/privacy" value={branding.privacy_url || ''} onChange={(e) => updateBranding('privacy_url', e.target.value)} />
              </div>
            </div>
            <div className="flex items-center gap-2">
              <button type="button" onClick={handleSaveBranding} disabled={brandingSaving} className="btn-primary text-sm">
                {brandingSaving ? 'Saving...' : 'Save Branding'}
              </button>
              {brandingSaved && <span className="text-sm text-green-600">Saved!</span>}
            </div>
          </div>
        </div>

        {/* System Info */}
        <div className="card p-5">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Activity className="w-5 h-5 text-brand-500" />
              <h3 className="text-lg font-semibold text-gray-900">System Info</h3>
            </div>
            <button type="button" onClick={loadHealth} className="btn-secondary text-xs py-1 px-3 flex items-center gap-1">
              <RefreshCw className={`w-3.5 h-3.5 ${healthLoading ? 'animate-spin' : ''}`} /> Refresh
            </button>
          </div>
          {healthLoading ? (
            <div className="animate-pulse space-y-2">
              <div className="h-4 bg-warm-300 rounded w-48" />
              <div className="h-4 bg-warm-300 rounded w-32" />
            </div>
          ) : health ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-500">Status</span>
                  <span className={`font-medium ${health.status === 'ok' || health.status === 'healthy' ? 'text-green-600' : 'text-red-600'}`}>
                    {health.status || '—'}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">Database</span>
                  <span className={`font-medium ${health.database === 'ok' || health.db_connected ? 'text-green-600' : 'text-red-600'}`}>
                    {health.database || (health.db_connected ? 'Connected' : 'Down')}
                  </span>
                </div>
                {health.version && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">API Version</span>
                    <span className="font-medium text-gray-900 font-mono text-xs">{health.version}</span>
                  </div>
                )}
                {health.uptime && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">Uptime</span>
                    <span className="font-medium text-gray-900">{health.uptime}</span>
                  </div>
                )}
              </div>
              <div className="space-y-2 text-sm">
                {health.go_version && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">Go Version</span>
                    <span className="font-medium text-gray-900 font-mono text-xs">{health.go_version}</span>
                  </div>
                )}
                {health.goroutines != null && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">Goroutines</span>
                    <span className="font-medium text-gray-900">{health.goroutines}</span>
                  </div>
                )}
                {health.memory_mb != null && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">Memory</span>
                    <span className="font-medium text-gray-900">{health.memory_mb} MB</span>
                  </div>
                )}
              </div>
            </div>
          ) : (
            <p className="text-sm text-gray-400">Could not fetch system health</p>
          )}
        </div>

        {/* Admin Users */}
        <div className="card p-5">
          <div className="flex items-center gap-2 mb-4">
            <Users className="w-5 h-5 text-brand-500" />
            <h3 className="text-lg font-semibold text-gray-900">Admin & Moderator Users</h3>
          </div>
          {adminLoading ? (
            <div className="animate-pulse space-y-2">
              <div className="h-4 bg-warm-300 rounded w-48" />
              <div className="h-4 bg-warm-300 rounded w-32" />
            </div>
          ) : adminUsers.length === 0 ? (
            <p className="text-sm text-gray-400">No admin or moderator users found</p>
          ) : (
            <div className="space-y-2">
              {adminUsers.map((u: any) => (
                <div key={u.id} className="flex items-center justify-between py-2 border-b border-warm-200 last:border-0">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 bg-brand-100 rounded-lg flex items-center justify-center text-brand-600 text-xs font-bold">
                      {(u.handle || u.email || '?')[0].toUpperCase()}
                    </div>
                    <div>
                      <p className="text-sm font-medium text-gray-800">{u.display_name || u.handle || u.email}</p>
                      <p className="text-xs text-gray-400">@{u.handle || '—'} · {u.email}</p>
                    </div>
                  </div>
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                    u.role === 'admin' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
                  }`}>
                    {u.role}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>

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
                placeholder="Leave blank to use environment default"
                value={apiUrl}
                onChange={(e) => setApiUrl(e.target.value)}
              />
              <p className="text-xs text-gray-400 mt-1">
                Override the default API URL. Leave blank to use the default from environment variables.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <button type="button" onClick={handleSaveApiUrl} className="btn-primary text-sm">
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
              <span className="text-gray-500">Auth method</span>
              <span className="text-gray-900 font-medium">
                HttpOnly Cookie
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-500">API URL</span>
              <span className="text-gray-900 font-medium font-mono text-xs">
                {process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080'}
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
    </AdminOnlyGuard>
  );
}
