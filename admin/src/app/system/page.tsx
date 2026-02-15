'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Activity, Database, RefreshCw, Server, Clock } from 'lucide-react';

export default function SystemPage() {
  const [health, setHealth] = useState<any>(null);
  const [auditLog, setAuditLog] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchData = () => {
    setLoading(true);
    Promise.all([api.getSystemHealth(), api.getAuditLog({ limit: 20 })])
      .then(([h, a]) => { setHealth(h); setAuditLog(a.entries || []); })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchData(); }, []);

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">System Health</h1>
          <p className="text-sm text-gray-500 mt-1">Monitor infrastructure and review audit log</p>
        </div>
        <button onClick={fetchData} className="btn-secondary text-sm flex items-center gap-1">
          <RefreshCw className="w-4 h-4" /> Refresh
        </button>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {[...Array(3)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-20 bg-warm-300 rounded" /></div>)}
        </div>
      ) : health ? (
        <div className="space-y-6">
          {/* Status Cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* Overall */}
            <div className="card p-5">
              <div className="flex items-center gap-3 mb-3">
                <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${health.status === 'healthy' ? 'bg-green-100 text-green-600' : 'bg-red-100 text-red-600'}`}>
                  <Server className="w-5 h-5" />
                </div>
                <div>
                  <p className="text-sm font-medium text-gray-500">API Server</p>
                  <p className={`text-lg font-bold ${health.status === 'healthy' ? 'text-green-600' : 'text-red-600'}`}>
                    {health.status === 'healthy' ? 'Healthy' : 'Unhealthy'}
                  </p>
                </div>
              </div>
            </div>

            {/* Database */}
            <div className="card p-5">
              <div className="flex items-center gap-3 mb-3">
                <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${health.database?.status === 'healthy' ? 'bg-green-100 text-green-600' : 'bg-red-100 text-red-600'}`}>
                  <Database className="w-5 h-5" />
                </div>
                <div>
                  <p className="text-sm font-medium text-gray-500">Database</p>
                  <p className={`text-lg font-bold ${health.database?.status === 'healthy' ? 'text-green-600' : 'text-red-600'}`}>
                    {health.database?.status === 'healthy' ? 'Connected' : 'Disconnected'}
                  </p>
                </div>
              </div>
              {health.database?.latency_ms != null && (
                <p className="text-xs text-gray-400 flex items-center gap-1"><Clock className="w-3 h-3" /> Latency: {health.database.latency_ms}ms</p>
              )}
              {health.database_size && (
                <p className="text-xs text-gray-400 mt-1">Size: {health.database_size}</p>
              )}
            </div>

            {/* Connection Pool */}
            <div className="card p-5">
              <div className="flex items-center gap-3 mb-3">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center bg-blue-100 text-blue-600">
                  <Activity className="w-5 h-5" />
                </div>
                <div>
                  <p className="text-sm font-medium text-gray-500">Connection Pool</p>
                  <p className="text-lg font-bold text-gray-900">
                    {health.connection_pool?.acquired || 0}/{health.connection_pool?.max || 0}
                  </p>
                </div>
              </div>
              {health.connection_pool && (
                <div className="space-y-1 text-xs text-gray-400">
                  <p>Total: {health.connection_pool.total} · Idle: {health.connection_pool.idle} · Acquired: {health.connection_pool.acquired}</p>
                  <div className="h-2 bg-warm-300 rounded-full overflow-hidden mt-1">
                    <div
                      className="h-full bg-brand-500 rounded-full"
                      style={{ width: `${health.connection_pool.max ? (health.connection_pool.acquired / health.connection_pool.max) * 100 : 0}%` }}
                    />
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Audit Log */}
          <div className="card overflow-hidden">
            <div className="px-5 py-4 border-b border-warm-300">
              <h3 className="text-lg font-semibold text-gray-900">Recent Audit Log</h3>
            </div>
            {auditLog.length === 0 ? (
              <div className="p-8 text-center text-gray-400 text-sm">No audit log entries yet</div>
            ) : (
              <table className="w-full">
                <thead className="bg-warm-200">
                  <tr>
                    <th className="table-header">Time</th>
                    <th className="table-header">Actor</th>
                    <th className="table-header">Action</th>
                    <th className="table-header">Target</th>
                    <th className="table-header">Details</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-warm-300">
                  {auditLog.map((entry) => (
                    <tr key={entry.id} className="hover:bg-warm-50">
                      <td className="table-cell text-xs text-gray-500">{formatDateTime(entry.created_at)}</td>
                      <td className="table-cell text-sm">@{entry.actor_handle || '—'}</td>
                      <td className="table-cell">
                        <span className="badge bg-blue-50 text-blue-700">{entry.action}</span>
                      </td>
                      <td className="table-cell text-xs text-gray-500">
                        {entry.target_type} {entry.target_id ? `(${String(entry.target_id).slice(0, 8)}...)` : ''}
                      </td>
                      <td className="table-cell text-xs text-gray-400 max-w-xs truncate">{entry.details || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      ) : (
        <div className="card p-8 text-center text-gray-500">Failed to load system health data.</div>
      )}
    </AdminShell>
  );
}
