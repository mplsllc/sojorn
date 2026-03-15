// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { Puzzle, RefreshCw, AlertTriangle } from 'lucide-react';

type Extension = {
  id: string;
  name: string;
  description: string;
  dependencies: string[];
  enabled: boolean;
};

export default function ExtensionsPage() {
  const [extensions, setExtensions] = useState<Extension[]>([]);
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const fetchExtensions = () => {
    setLoading(true);
    setError(null);
    api.listExtensions()
      .then(setExtensions)
      .catch(() => setError('Failed to load extensions'))
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchExtensions(); }, []);

  const handleToggle = async (id: string, enabled: boolean) => {
    setToggling(id);
    setError(null);
    try {
      await api.toggleExtension(id, enabled);
      setExtensions((prev) =>
        prev.map((ext) => (ext.id === id ? { ...ext, enabled } : ext))
      );
    } catch (err: any) {
      setError(err.message || 'Failed to toggle extension');
    } finally {
      setToggling(null);
    }
  };

  const enabledIds = new Set(extensions.filter((e) => e.enabled).map((e) => e.id));

  return (
    <AdminOnlyGuard>
      <AdminShell>
        <div className="mb-6 flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Extensions</h1>
            <p className="text-sm text-gray-500 mt-1">
              Enable or disable optional features for this instance
            </p>
          </div>
          <button onClick={fetchExtensions} className="btn-secondary text-sm flex items-center gap-1">
            <RefreshCw className="w-4 h-4" /> Refresh
          </button>
        </div>

        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 flex-shrink-0" />
            {error}
          </div>
        )}

        {loading ? (
          <div className="space-y-3">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="card p-5 animate-pulse">
                <div className="h-12 bg-warm-300 rounded" />
              </div>
            ))}
          </div>
        ) : extensions.length === 0 ? (
          <div className="card p-12 text-center text-gray-500">
            <Puzzle className="w-10 h-10 mx-auto mb-3 text-gray-300" />
            <p>No extensions registered. Run the database migration first.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {extensions.map((ext) => {
              const isToggling = toggling === ext.id;
              const hasMissingDeps = ext.dependencies.some((dep) => !enabledIds.has(dep));
              const canEnable = !hasMissingDeps;

              return (
                <div key={ext.id} className="card p-5 flex items-center justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h3 className="font-semibold text-gray-900">{ext.name}</h3>
                      <span className="text-xs font-mono text-gray-400">{ext.id}</span>
                      {ext.enabled && (
                        <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full">
                          Active
                        </span>
                      )}
                    </div>
                    <p className="text-sm text-gray-500 mt-0.5">{ext.description}</p>
                    {ext.dependencies.length > 0 && (
                      <p className="text-xs text-gray-400 mt-1">
                        Requires:{' '}
                        {ext.dependencies.map((dep) => (
                          <span
                            key={dep}
                            className={`font-mono ${enabledIds.has(dep) ? 'text-green-600' : 'text-red-500'}`}
                          >
                            {dep}
                          </span>
                        ))}
                      </p>
                    )}
                  </div>
                  <div className="ml-4">
                    <button
                      onClick={() => handleToggle(ext.id, !ext.enabled)}
                      disabled={isToggling || (!ext.enabled && !canEnable)}
                      className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 ${
                        ext.enabled ? 'bg-brand-500' : 'bg-gray-300'
                      } ${isToggling ? 'opacity-50' : ''} ${
                        !ext.enabled && !canEnable ? 'opacity-30 cursor-not-allowed' : 'cursor-pointer'
                      }`}
                    >
                      <span
                        className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                          ext.enabled ? 'translate-x-6' : 'translate-x-1'
                        }`}
                      />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        <div className="mt-8 p-4 bg-warm-100 rounded-lg text-sm text-gray-600">
          <p className="font-medium text-gray-700 mb-1">How extensions work</p>
          <ul className="list-disc list-inside space-y-1 text-gray-500">
            <li>Toggling an extension takes effect immediately — no restart needed</li>
            <li>Disabled extensions return 404 for their API routes</li>
            <li>The app hides UI for disabled extensions automatically</li>
            <li>Some extensions depend on others (e.g., Events requires Groups)</li>
          </ul>
        </div>
      </AdminShell>
    </AdminOnlyGuard>
  );
}
