// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { useEffect, useState, useCallback } from 'react';
import AdminShell from '@/components/AdminShell';
import SelectionBar from '@/components/SelectionBar';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import {
  ChevronLeft, ChevronRight, Search, RefreshCw, Trash2,
  Clock, CheckCircle, XCircle, Radio, Power, Zap,
} from 'lucide-react';

const SOURCE_LABELS: Record<string, string> = {
  mn511: 'MN511 Incidents',
  mn511_camera: 'MN511 Cameras',
  mn511_sign: 'MN511 Signs',
  mn511_weather: 'MN511 Weather',
  iced: 'IcedCoffee',
};

function severityBadge(sev: string) {
  const map: Record<string, string> = {
    critical: 'bg-red-100 text-red-800',
    high: 'bg-orange-100 text-orange-800',
    medium: 'bg-yellow-100 text-yellow-800',
    low: 'bg-blue-100 text-blue-800',
  };
  return map[sev] || 'bg-gray-100 text-gray-800';
}

function statusBadge(status: string) {
  return status === 'active'
    ? 'bg-green-100 text-green-800'
    : 'bg-gray-100 text-gray-600';
}

function timeAgo(dateStr: string | null): string {
  if (!dateStr) return 'Never';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

export default function BeaconAlertsPage() {
  // Stats
  const [stats, setStats] = useState<any>(null);

  // Feeds
  const [feeds, setFeeds] = useState<any[]>([]);
  const [syncingFeed, setSyncingFeed] = useState<string | null>(null);

  // Table
  const [items, setItems] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [offset, setOffset] = useState(0);
  const limit = 50;

  // Filters
  const [search, setSearch] = useState('');
  const [sourceFilter, setSourceFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [severityFilter, setSeverityFilter] = useState('');

  // Selection
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkLoading, setBulkLoading] = useState(false);

  const fetchAlerts = useCallback(() => {
    setLoading(true);
    api.listBeaconAlerts({
      limit, offset,
      search: search || undefined,
      source: sourceFilter || undefined,
      status: statusFilter || undefined,
      beacon_type: typeFilter || undefined,
      severity: severityFilter || undefined,
    })
      .then((data) => { setItems(data.items || []); setTotal(data.total || 0); })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [offset, search, sourceFilter, statusFilter, typeFilter, severityFilter]);

  const fetchStats = useCallback(() => {
    api.getBeaconAlertStats().then(setStats).catch(() => {});
  }, []);

  const fetchFeeds = useCallback(() => {
    api.getBeaconFeedStatus().then((d) => setFeeds(d.feeds || [])).catch(() => {});
  }, []);

  useEffect(() => { fetchAlerts(); }, [fetchAlerts]);
  useEffect(() => { fetchStats(); fetchFeeds(); }, []);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchAlerts();
  };

  const toggleSelect = (id: string) => {
    setSelected((prev) => {
      const s = new Set(prev);
      s.has(id) ? s.delete(id) : s.add(id);
      return s;
    });
  };
  const toggleAll = () => {
    if (selected.size === items.length) setSelected(new Set());
    else setSelected(new Set(items.map((i) => i.ID)));
  };

  const handleBulkAction = async (action: string) => {
    setBulkLoading(true);
    try {
      await api.bulkUpdateBeaconAlerts(Array.from(selected), action as any);
      setSelected(new Set());
      fetchAlerts();
      fetchStats();
    } catch (e: any) {
      alert(`Failed: ${e.message}`);
    }
    setBulkLoading(false);
  };

  const handleToggleFeed = async (source: string, enabled: boolean) => {
    await api.toggleBeaconFeed(source, enabled);
    fetchFeeds();
  };

  const handleSync = async (source?: string) => {
    setSyncingFeed(source || 'all');
    await api.triggerBeaconSync(source);
    setTimeout(() => { fetchFeeds(); fetchStats(); fetchAlerts(); setSyncingFeed(null); }, 3000);
  };

  const handleExpireSource = async (source: string) => {
    if (!confirm(`Expire ALL active alerts from ${SOURCE_LABELS[source] || source}?`)) return;
    await api.expireBeaconsBySource(source);
    fetchAlerts(); fetchStats(); fetchFeeds();
  };

  const handlePurgeSource = async (source: string) => {
    if (!confirm(`PERMANENTLY DELETE all alerts from ${SOURCE_LABELS[source] || source}? This cannot be undone.`)) return;
    await api.purgeBeaconsBySource(source);
    fetchAlerts(); fetchStats(); fetchFeeds();
  };

  return (
    <AdminShell>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Beacon Alerts</h1>
          <p className="text-sm text-gray-500 mt-1">
            {stats ? `${stats.total_count.toLocaleString()} total alerts` : 'Loading...'}
          </p>
        </div>
        <button onClick={() => handleSync()} disabled={syncingFeed !== null}
          className="btn-primary text-sm flex items-center gap-2">
          <RefreshCw className={`w-4 h-4 ${syncingFeed === 'all' ? 'animate-spin' : ''}`} />
          Sync All Feeds
        </button>
      </div>

      {/* Stats Cards */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3 mb-6">
          <StatCard label="Active" value={stats.active_count} color="text-green-700 bg-green-50" />
          <StatCard label="Expired" value={stats.expired_count} color="text-gray-600 bg-gray-50" />
          {Object.entries(stats.by_source as Record<string, number>).map(([src, count]) => (
            <StatCard key={src} label={SOURCE_LABELS[src] || src} value={count} color="text-blue-700 bg-blue-50" />
          ))}
        </div>
      )}

      {/* Feed Management */}
      <div className="card p-4 mb-6">
        <h2 className="text-sm font-semibold text-gray-900 mb-3">API Feeds</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {feeds.map((feed) => (
            <div key={feed.source} className={`border rounded-lg p-3 ${feed.enabled ? 'border-gray-200' : 'border-gray-100 bg-gray-50 opacity-60'}`}>
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <Radio className={`w-4 h-4 ${feed.enabled ? 'text-green-600' : 'text-gray-400'}`} />
                  <span className="text-sm font-medium">{SOURCE_LABELS[feed.source] || feed.source}</span>
                </div>
                <button
                  onClick={() => handleToggleFeed(feed.source, !feed.enabled)}
                  className={`p-1.5 rounded-lg transition-colors ${feed.enabled ? 'bg-green-100 text-green-700 hover:bg-green-200' : 'bg-gray-100 text-gray-400 hover:bg-gray-200'}`}
                  title={feed.enabled ? 'Disable feed' : 'Enable feed'}
                >
                  <Power className="w-3.5 h-3.5" />
                </button>
              </div>
              <div className="text-xs text-gray-500 space-y-0.5 mb-2">
                <div>Last sync: {timeAgo(feed.last_sync_at)}</div>
                <div>Alerts: {feed.alert_count.toLocaleString()}</div>
                {feed.last_error && (
                  <div className="text-red-600 truncate" title={feed.last_error}>Error: {feed.last_error}</div>
                )}
              </div>
              <div className="flex gap-1.5">
                <button onClick={() => handleSync(feed.source)} disabled={syncingFeed !== null}
                  className="text-xs px-2 py-1 rounded bg-blue-50 text-blue-700 hover:bg-blue-100 flex items-center gap-1">
                  <Zap className={`w-3 h-3 ${syncingFeed === feed.source ? 'animate-spin' : ''}`} /> Sync
                </button>
                <button onClick={() => handleExpireSource(feed.source)}
                  className="text-xs px-2 py-1 rounded bg-yellow-50 text-yellow-700 hover:bg-yellow-100">
                  Expire All
                </button>
                <button onClick={() => handlePurgeSource(feed.source)}
                  className="text-xs px-2 py-1 rounded bg-red-50 text-red-700 hover:bg-red-100">
                  Purge
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Filter Bar */}
      <div className="card p-4 mb-4 flex flex-wrap gap-3 items-center">
        <form onSubmit={handleSearch} className="flex-1 min-w-[200px] relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input className="input pl-10" placeholder="Search title or body..." value={search}
            onChange={(e) => setSearch(e.target.value)} />
        </form>
        <select className="input w-auto" value={sourceFilter}
          onChange={(e) => { setSourceFilter(e.target.value); setOffset(0); }}>
          <option value="">All Sources</option>
          <option value="mn511">MN511 Incidents</option>
          <option value="mn511_camera">MN511 Cameras</option>
          <option value="mn511_sign">MN511 Signs</option>
          <option value="mn511_weather">MN511 Weather</option>
          <option value="iced">IcedCoffee</option>
        </select>
        <select className="input w-auto" value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setOffset(0); }}>
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="expired">Expired</option>
        </select>
        <select className="input w-auto" value={typeFilter}
          onChange={(e) => { setTypeFilter(e.target.value); setOffset(0); }}>
          <option value="">All Types</option>
          <option value="safety">Safety</option>
          <option value="hazard">Hazard</option>
          <option value="checkpoint">Checkpoint</option>
          <option value="camera">Camera</option>
          <option value="sign">Sign</option>
          <option value="weather_station">Weather Station</option>
        </select>
        <select className="input w-auto" value={severityFilter}
          onChange={(e) => { setSeverityFilter(e.target.value); setOffset(0); }}>
          <option value="">All Severities</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>
      </div>

      {/* Selection Bar */}
      <SelectionBar
        count={selected.size}
        total={items.length}
        onSelectAll={() => setSelected(new Set(items.map((i) => i.ID)))}
        onClearSelection={() => setSelected(new Set())}
        loading={bulkLoading}
        actions={[
          { label: 'Expire', action: 'expire', confirm: true, color: 'bg-yellow-50 text-yellow-800 hover:bg-yellow-100', icon: <Clock className="w-3.5 h-3.5" /> },
          { label: 'Reactivate', action: 'reactivate', color: 'bg-green-50 text-green-700 hover:bg-green-100', icon: <CheckCircle className="w-3.5 h-3.5" /> },
          { label: 'Delete', action: 'delete', confirm: true, color: 'bg-red-100 text-red-800 hover:bg-red-200', icon: <Trash2 className="w-3.5 h-3.5" /> },
        ]}
        onAction={handleBulkAction}
      />

      {/* Alerts Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-warm-200">
              <tr>
                <th className="table-header w-10">
                  <input type="checkbox" checked={items.length > 0 && selected.size === items.length}
                    onChange={toggleAll} className="rounded border-gray-300" />
                </th>
                <th className="table-header">Title / Body</th>
                <th className="table-header">Source</th>
                <th className="table-header">Type</th>
                <th className="table-header">Severity</th>
                <th className="table-header">Status</th>
                <th className="table-header">Location</th>
                <th className="table-header">Expires</th>
                <th className="table-header">Created</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-warm-300">
              {loading ? (
                [...Array(5)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(9)].map((_, j) => (
                      <td key={j} className="table-cell">
                        <div className="h-4 bg-warm-300 rounded animate-pulse w-20" />
                      </td>
                    ))}
                  </tr>
                ))
              ) : items.length === 0 ? (
                <tr>
                  <td colSpan={9} className="table-cell text-center text-gray-400 py-8">
                    No beacon alerts found
                  </td>
                </tr>
              ) : (
                items.map((item) => (
                  <tr key={item.ID} className={`hover:bg-warm-50 ${selected.has(item.ID) ? 'bg-brand-50' : ''}`}>
                    <td className="table-cell">
                      <input type="checkbox" checked={selected.has(item.ID)}
                        onChange={() => toggleSelect(item.ID)} className="rounded border-gray-300" />
                    </td>
                    <td className="table-cell max-w-[300px]">
                      <div className="truncate text-sm font-medium text-gray-900" title={item.Title}>
                        {item.Title || '(no title)'}
                      </div>
                      {item.Body && item.Body !== item.Title && (
                        <div className="truncate text-xs text-gray-500 mt-0.5" title={item.Body}>
                          {item.Body.slice(0, 100)}
                        </div>
                      )}
                    </td>
                    <td className="table-cell">
                      <span className="text-xs text-gray-600">{SOURCE_LABELS[item.Source] || item.Source}</span>
                    </td>
                    <td className="table-cell">
                      <span className="text-xs">{item.BeaconType}</span>
                    </td>
                    <td className="table-cell">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${severityBadge(item.Severity)}`}>
                        {item.Severity}
                      </span>
                    </td>
                    <td className="table-cell">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${statusBadge(item.Status)}`}>
                        {item.Status}
                      </span>
                    </td>
                    <td className="table-cell">
                      <span className="text-xs text-gray-500">
                        {item.Lat.toFixed(4)}, {item.Lng.toFixed(4)}
                      </span>
                    </td>
                    <td className="table-cell">
                      <span className="text-xs text-gray-500">
                        {item.ExpiresAt ? timeAgo(item.ExpiresAt) : '—'}
                      </span>
                    </td>
                    <td className="table-cell">
                      <span className="text-xs text-gray-500">
                        {formatDateTime(item.CreatedAt)}
                      </span>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        <div className="border-t border-warm-300 px-4 py-3 flex items-center justify-between">
          <p className="text-sm text-gray-500">
            {total > 0 ? `${offset + 1}\u2013${Math.min(offset + limit, total)} of ${total.toLocaleString()}` : 'No results'}
          </p>
          <div className="flex gap-2">
            <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset === 0}
              onClick={() => { setOffset(Math.max(0, offset - limit)); setSelected(new Set()); }}>
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset + limit >= total}
              onClick={() => { setOffset(offset + limit); setSelected(new Set()); }}>
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </AdminShell>
  );
}

function StatCard({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className={`rounded-lg p-3 ${color}`}>
      <div className="text-lg font-bold">{value.toLocaleString()}</div>
      <div className="text-xs opacity-75">{label}</div>
    </div>
  );
}
