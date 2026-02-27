// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { statusColor, formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { ShieldAlert, CheckCircle, XCircle, Lock } from 'lucide-react';

export default function CapsuleReportsPage() {
  const [reports, setReports] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [violationFilter, setViolationFilter] = useState('');
  const [sortOrder, setSortOrder] = useState('');
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  const fetchReports = () => {
    setLoading(true);
    api.listCapsuleReports({ limit: 50, status: statusFilter || undefined })
      .then((data) => { setReports(data.reports); setTotal(data.total); })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchReports(); }, [statusFilter]);

  const violationTypes = Array.from(new Set(reports.map((r) => r.reason).filter(Boolean)));

  const filteredReports = (() => {
    let result = reports;
    if (violationFilter) result = result.filter((r) => r.reason === violationFilter);
    if (sortOrder === 'oldest') result = [...result].sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
    return result;
  })();

  const handleUpdate = async (id: string, status: string) => {
    try {
      await api.updateCapsuleReportStatus(id, status);
      fetchReports();
    } catch {}
  };

  const toggleExpand = (id: string) => {
    setExpanded((prev) => {
      const s = new Set(prev);
      s.has(id) ? s.delete(id) : s.add(id);
      return s;
    });
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Lock className="w-5 h-5 text-gray-600" />
            <h1 className="text-2xl font-bold text-gray-900">Capsule Reports</h1>
          </div>
          <p className="text-sm text-gray-500 mt-1">
            {total} {statusFilter || 'total'} reports from encrypted private groups.
            Members voluntarily submitted decrypted evidence.
          </p>
        </div>
        <div className="flex gap-3">
          <select className="input w-auto" title="Filter by status" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
            <option value="">All Statuses</option>
            <option value="pending">Pending</option>
            <option value="reviewed">Reviewed</option>
            <option value="actioned">Actioned</option>
            <option value="dismissed">Dismissed</option>
          </select>
          {violationTypes.length > 1 && (
            <select className="input w-auto" title="Filter by violation type" value={violationFilter} onChange={(e) => setViolationFilter(e.target.value)}>
              <option value="">All Violations</option>
              {violationTypes.map((v) => <option key={v} value={v}>{v}</option>)}
            </select>
          )}
          <select className="input w-auto" title="Sort order" value={sortOrder} onChange={(e) => setSortOrder(e.target.value)}>
            <option value="">Newest</option>
            <option value="oldest">Oldest</option>
          </select>
        </div>
      </div>

      {loading ? (
        <div className="space-y-4">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="card p-6 animate-pulse">
              <div className="h-16 bg-warm-300 rounded" />
            </div>
          ))}
        </div>
      ) : filteredReports.length === 0 ? (
        <div className="card p-12 text-center">
          <ShieldAlert className="w-12 h-12 text-green-400 mx-auto mb-3" />
          <p className="text-gray-500 font-medium">No {statusFilter || ''} capsule reports</p>
        </div>
      ) : (
        <div className="card overflow-hidden">
          <table className="w-full">
            <thead className="bg-warm-200">
              <tr>
                <th className="table-header">Reporter</th>
                <th className="table-header">Capsule Group</th>
                <th className="table-header">Reason</th>
                <th className="table-header">Evidence (decrypted by reporter)</th>
                <th className="table-header">Status</th>
                <th className="table-header">Date</th>
                <th className="table-header">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-warm-300">
              {filteredReports.map((report) => {
                const isExpanded = expanded.has(report.id);
                const sample = report.decrypted_sample as string | null;
                return (
                  <tr key={report.id} className="hover:bg-warm-50 transition-colors align-top">
                    <td className="table-cell text-sm text-brand-600">
                      @{report.reporter_handle || '—'}
                    </td>
                    <td className="table-cell">
                      <span className="inline-flex items-center gap-1 text-sm">
                        <Lock className="w-3 h-3 text-gray-400 shrink-0" />
                        {report.capsule_name || report.capsule_id}
                      </span>
                    </td>
                    <td className="table-cell">
                      <span className="badge bg-orange-50 text-orange-700">{report.reason}</span>
                    </td>
                    <td className="table-cell max-w-xs">
                      {sample ? (
                        <div>
                          <p className={`text-sm text-gray-700 ${isExpanded ? '' : 'line-clamp-2'}`}>
                            {sample}
                          </p>
                          {sample.length > 120 && (
                            <button
                              className="text-xs text-brand-500 hover:underline mt-1"
                              onClick={() => toggleExpand(report.id)}
                            >
                              {isExpanded ? 'Show less' : 'Show more'}
                            </button>
                          )}
                        </div>
                      ) : (
                        <span className="text-xs text-gray-400 italic">No evidence provided</span>
                      )}
                    </td>
                    <td className="table-cell">
                      <span className={`badge ${statusColor(report.status)}`}>{report.status}</span>
                    </td>
                    <td className="table-cell text-xs text-gray-500">
                      {formatDateTime(report.created_at)}
                    </td>
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
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </AdminShell>
  );
}
