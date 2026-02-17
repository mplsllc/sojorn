'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDate } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { RefreshCw, Wrench, Play, CheckCircle } from 'lucide-react';

export default function QuipsPage() {
  const [quips, setQuips] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [repairing, setRepairing] = useState<Set<string>>(new Set());
  const [repaired, setRepaired] = useState<Set<string>>(new Set());

  const fetchQuips = () => {
    setLoading(true);
    api.getBrokenQuips()
      .then((data) => setQuips(data.quips ?? []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchQuips(); }, []);

  const repairQuip = async (quip: any) => {
    setRepairing((prev) => new Set(prev).add(quip.id));
    try {
      await api.repairQuip(quip.id);
      setRepaired((prev) => new Set(prev).add(quip.id));
      setQuips((prev) => prev.filter((q) => q.id !== quip.id));
    } catch (e: any) {
      alert(`Repair failed: ${e.message}`);
    } finally {
      setRepairing((prev) => { const s = new Set(prev); s.delete(quip.id); return s; });
    }
  };

  const repairAll = async () => {
    const list = [...quips];
    for (const q of list) {
      await repairQuip(q);
    }
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Quip Repair</h1>
          <p className="text-sm text-gray-500 mt-1">
            Videos missing thumbnails — server extracts frames via FFmpeg and uploads to R2.
          </p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={fetchQuips}
            className="flex items-center gap-1.5 px-3 py-2 border rounded-lg text-sm hover:bg-gray-50"
          >
            <RefreshCw className="w-4 h-4" /> Reload
          </button>
          {quips.length > 0 && (
            <button
              onClick={repairAll}
              className="flex items-center gap-1.5 px-4 py-2 bg-blue-700 text-white rounded-lg text-sm font-medium hover:bg-blue-800"
            >
              <Wrench className="w-4 h-4" /> Repair All ({quips.length})
            </button>
          )}
        </div>
      </div>

      {repaired.size > 0 && (
        <div className="mb-4 px-4 py-2.5 bg-green-50 border border-green-200 rounded-lg text-sm text-green-700 flex items-center gap-2">
          <CheckCircle className="w-4 h-4" /> {repaired.size} quip{repaired.size !== 1 ? 's' : ''} repaired this session.
        </div>
      )}

      <div className="bg-white rounded-xl border overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-gray-400">Loading…</div>
        ) : quips.length === 0 ? (
          <div className="p-8 text-center text-gray-400">
            {repaired.size > 0 ? '✓ All quips repaired!' : 'No broken quips found.'}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Post ID</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Video URL</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Created</th>
                <th className="px-4 py-3 text-right font-medium text-gray-600">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {quips.map((q) => (
                <tr key={q.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono text-xs text-gray-500">{q.id.slice(0, 8)}…</td>
                  <td className="px-4 py-3 max-w-xs">
                    <span className="truncate block text-xs text-gray-600" title={q.video_url}>
                      {q.video_url}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-500">{formatDate(q.created_at)}</td>
                  <td className="px-4 py-3 text-right">
                    <button
                      onClick={() => repairQuip(q)}
                      disabled={repairing.has(q.id)}
                      className="flex items-center gap-1.5 ml-auto px-3 py-1.5 bg-amber-500 text-white rounded-lg text-xs font-medium hover:bg-amber-600 disabled:opacity-50"
                    >
                      {repairing.has(q.id) ? (
                        <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                      ) : (
                        <Play className="w-3.5 h-3.5" />
                      )}
                      {repairing.has(q.id) ? 'Repairing…' : 'Repair'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </AdminShell>
  );
}
