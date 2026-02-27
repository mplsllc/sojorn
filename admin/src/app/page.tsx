// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Users, FileText, Shield, Scale, Flag, TrendingDown, UserPlus, Bot, Brain, Activity } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line } from 'recharts';

function StatCard({ label, value, sub, borderColor, icon: Icon, href }: { label: string; value: number | string; sub?: string; borderColor: string; icon: any; href?: string }) {
  const inner = (
    <div className={`card p-5 border-t-4 ${borderColor} ${href ? 'hover:shadow-md transition-shadow cursor-pointer' : ''}`}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm font-medium text-gray-500">{label}</p>
          <p className="text-2xl font-bold text-gray-900 mt-1">{value}</p>
          {sub && <p className="text-xs text-gray-400 mt-1">{sub}</p>}
        </div>
        <Icon className="w-8 h-8 text-gray-300" />
      </div>
    </div>
  );
  return href ? <a href={href}>{inner}</a> : inner;
}

export default function DashboardPage() {
  const [stats, setStats] = useState<any>(null);
  const [growth, setGrowth] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'activity' | 'moderation' | 'official' | 'ai'>('activity');
  const [auditLog, setAuditLog] = useState<any[]>([]);
  const [modQueue, setModQueue] = useState<any[]>([]);
  const [officialAccounts, setOfficialAccounts] = useState<any[]>([]);
  const [aiEngines, setAiEngines] = useState<any>(null);

  useEffect(() => {
    Promise.all([api.getDashboardStats(), api.getGrowthStats(30)])
      .then(([s, g]) => { setStats(s); setGrowth(g); })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  const loadTab = (t: typeof tab) => {
    setTab(t);
    if (t === 'activity' && auditLog.length === 0) {
      api.getAuditLog({ limit: 10 }).then((d) => setAuditLog(d.entries ?? d.logs ?? [])).catch(() => {});
    }
    if (t === 'moderation' && modQueue.length === 0) {
      api.getModerationQueue({ limit: 5 }).then((d) => setModQueue(d.items ?? d.flags ?? [])).catch(() => {});
    }
    if (t === 'official' && officialAccounts.length === 0) {
      api.listOfficialAccounts().then((d) => setOfficialAccounts(d.accounts ?? d ?? [])).catch(() => {});
    }
    if (t === 'ai' && !aiEngines) {
      api.getAIEngines().then(setAiEngines).catch(() => {});
    }
  };

  useEffect(() => { loadTab('activity'); }, []);

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="text-sm text-gray-500 mt-1">Overview of Sojorn platform activity</p>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="card p-5 animate-pulse">
              <div className="h-4 bg-warm-300 rounded w-24 mb-3" />
              <div className="h-8 bg-warm-300 rounded w-16" />
            </div>
          ))}
        </div>
      ) : stats ? (
        <>
          {/* 5 Top Stat Cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-4 mb-6">
            <StatCard label="Total Users" value={stats.users?.total || 0} sub={`${stats.users?.new_today || 0} new today`} borderColor="border-purple-500" icon={Users} href="/users" />
            <StatCard label="Posts Today" value={stats.posts?.new_today || 0} sub={`${stats.posts?.total || 0} total`} borderColor="border-green-500" icon={FileText} href="/posts" />
            <StatCard label="Pending Reviews" value={stats.moderation?.pending_flags || 0} sub="moderation queue" borderColor="border-orange-500" icon={Shield} href="/moderation" />
            <StatCard label="Open Reports" value={stats.reports?.pending || 0} sub={`${stats.appeals?.pending || 0} appeals`} borderColor="border-red-500" icon={Flag} href="/reports" />
            <StatCard label="Active Users" value={stats.users?.active || 0} sub={`${stats.users?.banned || 0} banned`} borderColor="border-cyan-500" icon={UserPlus} href="/users" />
          </div>

          {/* Secondary Stats Row */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
            <a href="/moderation" className="card p-4 text-center hover:shadow-md transition-shadow">
              <p className="text-lg font-bold text-gray-900">{stats.posts?.flagged || 0}</p>
              <p className="text-xs text-gray-500">Flagged Posts</p>
            </a>
            <a href="/appeals" className="card p-4 text-center hover:shadow-md transition-shadow">
              <p className="text-lg font-bold text-gray-900">{stats.appeals?.pending || 0}</p>
              <p className="text-xs text-gray-500">Pending Appeals</p>
            </a>
            <a href="/users?status=banned" className="card p-4 text-center hover:shadow-md transition-shadow">
              <p className="text-lg font-bold text-gray-900">{stats.users?.banned || 0}</p>
              <p className="text-xs text-gray-500">Banned Users</p>
            </a>
            <a href="/users?status=suspended" className="card p-4 text-center hover:shadow-md transition-shadow">
              <p className="text-lg font-bold text-gray-900">{stats.users?.suspended || 0}</p>
              <p className="text-xs text-gray-500">Suspended</p>
            </a>
          </div>

          {/* Tabbed Content Area */}
          <div className="card mb-6">
            <div className="border-b border-warm-300 px-4 flex gap-1">
              {[
                { key: 'activity', label: 'Activity Log', icon: Activity },
                { key: 'moderation', label: 'Moderation Queue', icon: Shield },
                { key: 'official', label: 'Official Accounts', icon: Bot },
                { key: 'ai', label: 'AI Status', icon: Brain },
              ].map((t) => (
                <button
                  key={t.key}
                  type="button"
                  onClick={() => loadTab(t.key as typeof tab)}
                  className={`flex items-center gap-1.5 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
                    tab === t.key
                      ? 'border-brand-500 text-brand-600'
                      : 'border-transparent text-gray-500 hover:text-gray-700'
                  }`}
                >
                  <t.icon className="w-4 h-4" /> {t.label}
                </button>
              ))}
            </div>
            <div className="p-5">
              {tab === 'activity' && (
                <div>
                  {auditLog.length === 0 ? (
                    <p className="text-sm text-gray-400">No recent activity</p>
                  ) : (
                    <div className="space-y-2">
                      {auditLog.slice(0, 10).map((log: any, i: number) => (
                        <div key={log.id || i} className="flex items-center justify-between py-2 border-b border-warm-200 last:border-0">
                          <div className="flex items-center gap-3">
                            <div className="w-8 h-8 bg-warm-200 rounded-lg flex items-center justify-center text-xs font-bold text-gray-500">
                              {(log.action || '?')[0].toUpperCase()}
                            </div>
                            <div>
                              <p className="text-sm font-medium text-gray-800">{log.action}</p>
                              <p className="text-xs text-gray-400">{log.target_type} · {log.target_id?.slice(0, 8)}…</p>
                            </div>
                          </div>
                          <span className="text-xs text-gray-400">{log.created_at ? formatDateTime(log.created_at) : ''}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {tab === 'moderation' && (
                <div>
                  {modQueue.length === 0 ? (
                    <p className="text-sm text-gray-400">Moderation queue is clear</p>
                  ) : (
                    <div className="space-y-2">
                      {modQueue.slice(0, 5).map((item: any, i: number) => (
                        <div key={item.id || i} className="flex items-center justify-between py-2 border-b border-warm-200 last:border-0">
                          <div>
                            <p className="text-sm font-medium text-gray-800">{item.flag_reason || item.reason || 'Flagged content'}</p>
                            <p className="text-xs text-gray-400">{item.content_type} · {item.status}</p>
                          </div>
                          <a href="/moderation" className="text-xs text-brand-500 hover:text-brand-700 font-medium">Review</a>
                        </div>
                      ))}
                    </div>
                  )}
                  <a href="/moderation" className="text-sm text-brand-500 hover:text-brand-700 font-medium mt-3 block">View All →</a>
                </div>
              )}

              {tab === 'official' && (
                <div>
                  {officialAccounts.length === 0 ? (
                    <p className="text-sm text-gray-400">No official accounts configured</p>
                  ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                      {officialAccounts.map((acc: any) => (
                        <div key={acc.id} className="border border-warm-300 rounded-lg p-3">
                          <div className="flex items-center justify-between">
                            <p className="text-sm font-medium text-gray-800">{acc.display_name || acc.handle || acc.id?.slice(0, 8)}</p>
                            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${acc.enabled ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
                              {acc.enabled ? 'Active' : 'Disabled'}
                            </span>
                          </div>
                          <p className="text-xs text-gray-400 mt-1">{acc.source_type || acc.type || '—'}</p>
                        </div>
                      ))}
                    </div>
                  )}
                  <a href="/official-accounts" className="text-sm text-brand-500 hover:text-brand-700 font-medium mt-3 block">Manage →</a>
                </div>
              )}

              {tab === 'ai' && (
                <div>
                  {!aiEngines ? (
                    <p className="text-sm text-gray-400">Loading AI engine status…</p>
                  ) : (
                    <div className="space-y-3">
                      {(aiEngines.engines ?? []).map((eng: any) => (
                        <div key={eng.name} className="flex items-center justify-between py-2 border-b border-warm-200 last:border-0">
                          <div>
                            <p className="text-sm font-medium text-gray-800">{eng.name}</p>
                            <p className="text-xs text-gray-400">{eng.description || eng.type || '—'}</p>
                          </div>
                          <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${eng.available || eng.healthy ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                            {eng.available || eng.healthy ? 'Healthy' : 'Down'}
                          </span>
                        </div>
                      ))}
                      {(aiEngines.engines ?? []).length === 0 && <p className="text-sm text-gray-400">No AI engines configured</p>}
                    </div>
                  )}
                  <a href="/ai-moderation" className="text-sm text-brand-500 hover:text-brand-700 font-medium mt-3 block">Configure →</a>
                </div>
              )}
            </div>
          </div>

          {/* Charts */}
          {growth && (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
              <div className="card p-5">
                <h3 className="text-sm font-semibold text-gray-700 mb-4">User Growth (30 days)</h3>
                <div className="h-64">
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={growth.user_growth || []}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#E8E6E1" />
                      <XAxis dataKey="date" tick={{ fontSize: 11 }} tickFormatter={(v) => v.slice(5)} />
                      <YAxis tick={{ fontSize: 11 }} />
                      <Tooltip />
                      <Line type="monotone" dataKey="count" stroke="#6B5B95" strokeWidth={2} dot={false} />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              </div>
              <div className="card p-5">
                <h3 className="text-sm font-semibold text-gray-700 mb-4">Post Activity (30 days)</h3>
                <div className="h-64">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={growth.post_growth || []}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#E8E6E1" />
                      <XAxis dataKey="date" tick={{ fontSize: 11 }} tickFormatter={(v) => v.slice(5)} />
                      <YAxis tick={{ fontSize: 11 }} />
                      <Tooltip />
                      <Bar dataKey="count" fill="#6B5B95" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </div>
            </div>
          )}

          {/* Quick Actions */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-3">Quick Actions</h3>
            <div className="flex flex-wrap gap-3">
              <a href="/moderation" className="btn-primary text-sm flex items-center gap-2">
                <Shield className="w-4 h-4" /> Review Moderation Queue ({stats.moderation?.pending_flags || 0})
              </a>
              <a href="/appeals" className="btn-secondary text-sm flex items-center gap-2">
                <Scale className="w-4 h-4" /> Review Appeals ({stats.appeals?.pending || 0})
              </a>
              <a href="/reports" className="btn-secondary text-sm flex items-center gap-2">
                <Flag className="w-4 h-4" /> Review Reports ({stats.reports?.pending || 0})
              </a>
            </div>
          </div>
        </>
      ) : (
        <div className="card p-8 text-center text-gray-500">Failed to load dashboard data.</div>
      )}
    </AdminShell>
  );
}
