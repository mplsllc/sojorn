// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import SelectionBar from '@/components/SelectionBar';
import { api } from '@/lib/api';
import { statusColor, formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Flag, CheckCircle, XCircle, AlertTriangle, Building2, Users, MessageSquare } from 'lucide-react';
import Link from 'next/link';

const contextFilters = [
  { value: '', label: 'All Reports' },
  { value: 'user', label: 'User Reports' },
  { value: 'neighborhood', label: 'Neighborhood' },
  { value: 'group', label: 'Group / Capsule' },
];

export default function ReportsPage() {
  const [reports, setReports] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [contextFilter, setContextFilter] = useState('');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkLoading, setBulkLoading] = useState(false);

  const fetchReports = () => {
    setLoading(true);
    api.listReports({ limit: 50, status: statusFilter, context: contextFilter || undefined })
      .then((data) => { setReports(data.reports); setTotal(data.total); })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchReports(); }, [statusFilter, contextFilter]);

  const handleUpdate = async (id: string, status: string) => {
    try {
      await api.updateReportStatus(id, status);
      fetchReports();
    } catch {}
  };

  const toggleSelect = (id: string) => {
    setSelected((prev) => { const s = new Set(prev); s.has(id) ? s.delete(id) : s.add(id); return s; });
  };
  const toggleAll = () => {
    if (selected.size === reports.length) setSelected(new Set());
    else setSelected(new Set(reports.map((r) => r.id)));
  };

  const handleBulkAction = async (action: string) => {
    setBulkLoading(true);
    try {
      await api.bulkUpdateReports(Array.from(selected), action);
      setSelected(new Set());
      fetchReports();
    } catch {}
    setBulkLoading(false);
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Reports</h1>
          <p className="text-sm text-gray-500 mt-1">{total} {statusFilter} reports</p>
        </div>
        <select className="input w-auto" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="pending">Pending</option>
          <option value="reviewed">Reviewed</option>
          <option value="actioned">Actioned</option>
          <option value="dismissed">Dismissed</option>
        </select>
      </div>

      <div className="mb-4 flex gap-2">
        {contextFilters.map((f) => (
          <button
            key={f.value}
            type="button"
            onClick={() => setContextFilter(f.value)}
            className={`px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
              contextFilter === f.value
                ? 'bg-brand-600 text-white'
                : 'bg-warm-200 text-gray-600 hover:bg-warm-300'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {statusFilter === 'pending' && (
        <SelectionBar
          count={selected.size}
          total={reports.length}
          onSelectAll={() => setSelected(new Set(reports.map((r) => r.id)))}
          onClearSelection={() => setSelected(new Set())}
          loading={bulkLoading}
          actions={[
            { label: 'Action All', action: 'actioned', color: 'bg-green-50 text-green-700 hover:bg-green-100', icon: <CheckCircle className="w-3.5 h-3.5" /> },
            { label: 'Dismiss All', action: 'dismissed', color: 'bg-gray-100 text-gray-700 hover:bg-gray-200', icon: <XCircle className="w-3.5 h-3.5" /> },
          ]}
          onAction={handleBulkAction}
        />
      )}

      {loading ? (
        <div className="space-y-4">
          {[...Array(3)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-16 bg-warm-300 rounded" /></div>)}
        </div>
      ) : reports.length === 0 ? (
        <div className="card p-12 text-center">
          <Flag className="w-12 h-12 text-green-400 mx-auto mb-3" />
          <p className="text-gray-500 font-medium">No {statusFilter} reports</p>
        </div>
      ) : (
        <div className="card overflow-hidden">
          <table className="w-full">
            <thead className="bg-warm-200">
              <tr>
                {statusFilter === 'pending' && (
                  <th className="table-header w-10">
                    <input type="checkbox" className="rounded border-gray-300" checked={reports.length > 0 && selected.size === reports.length} onChange={toggleAll} />
                  </th>
                )}
                <th className="table-header">Reporter</th>
                <th className="table-header">Target</th>
                <th className="table-header">Type</th>
                <th className="table-header">Context</th>
                <th className="table-header">Description</th>
                <th className="table-header">Content</th>
                <th className="table-header">Status</th>
                <th className="table-header">Date</th>
                <th className="table-header">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-warm-300">
              {reports.map((report) => (
                <tr key={report.id} className={`hover:bg-warm-50 transition-colors ${selected.has(report.id) ? 'bg-brand-50' : ''}`}>
                  {statusFilter === 'pending' && (
                    <td className="table-cell">
                      <input type="checkbox" className="rounded border-gray-300" checked={selected.has(report.id)} onChange={() => toggleSelect(report.id)} />
                    </td>
                  )}
                  <td className="table-cell">
                    <Link href={`/users/${report.reporter_id}`} className="text-brand-500 hover:text-brand-700 text-sm">
                      @{report.reporter_handle || '—'}
                    </Link>
                  </td>
                  <td className="table-cell">
                    <Link href={`/users/${report.target_user_id}`} className="text-brand-500 hover:text-brand-700 text-sm">
                      @{report.target_handle || '—'}
                    </Link>
                  </td>
                  <td className="table-cell">
                    <span className="badge bg-orange-50 text-orange-700">
                      <AlertTriangle className="w-3 h-3 mr-1" />{report.violation_type}
                    </span>
                  </td>
                  <td className="table-cell">
                    {report.group_name && (
                      <span className="badge bg-purple-50 text-purple-700 text-xs">
                        <MessageSquare className="w-3 h-3 mr-1" />{report.group_name}
                      </span>
                    )}
                    {report.neighborhood_name && (
                      <span className="badge bg-blue-50 text-blue-700 text-xs">
                        <Building2 className="w-3 h-3 mr-1" />{report.neighborhood_name}
                      </span>
                    )}
                    {!report.group_name && !report.neighborhood_name && (
                      <span className="text-xs text-gray-400">—</span>
                    )}
                  </td>
                  <td className="table-cell max-w-xs">
                    <p className="text-sm text-gray-700 line-clamp-2">{report.description}</p>
                  </td>
                  <td className="table-cell text-xs text-gray-500">
                    {report.post_id && <Link href={`/posts/${report.post_id}`} className="text-brand-500 hover:text-brand-700">View Post</Link>}
                  </td>
                  <td className="table-cell">
                    <span className={`badge ${statusColor(report.status)}`}>{report.status}</span>
                  </td>
                  <td className="table-cell text-xs text-gray-500">{formatDateTime(report.created_at)}</td>
                  <td className="table-cell">
                    {report.status === 'pending' && (
                      <div className="flex gap-1">
                        <button
                          onClick={() => handleUpdate(report.id, 'actioned')}
                          className="p-1.5 bg-green-50 text-green-700 rounded hover:bg-green-100"
                          title="Action taken"
                        >
                          <CheckCircle className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => handleUpdate(report.id, 'dismissed')}
                          className="p-1.5 bg-gray-50 text-gray-600 rounded hover:bg-gray-100"
                          title="Dismiss"
                        >
                          <XCircle className="w-4 h-4" />
                        </button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </AdminShell>
  );
}
