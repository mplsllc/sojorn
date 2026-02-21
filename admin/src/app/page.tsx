// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { Users, FileText, Shield, Scale, Flag, TrendingUp, TrendingDown, UserPlus } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line } from 'recharts';

function StatCard({ label, value, icon: Icon, sub, color }: { label: string; value: number | string; icon: any; sub?: string; color: string }) {
  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm font-medium text-gray-500">{label}</p>
          <p className="text-2xl font-bold text-gray-900 mt-1">{value}</p>
          {sub && <p className="text-xs text-gray-400 mt-1">{sub}</p>}
        </div>
        <div className={`w-12 h-12 rounded-xl flex items-center justify-center ${color}`}>
          <Icon className="w-6 h-6" />
        </div>
      </div>
    </div>
  );
}

export default function DashboardPage() {
  const [stats, setStats] = useState<any>(null);
  const [growth, setGrowth] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([api.getDashboardStats(), api.getGrowthStats(30)])
      .then(([s, g]) => { setStats(s); setGrowth(g); })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="text-sm text-gray-500 mt-1">Overview of Sojorn platform activity</p>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {[...Array(8)].map((_, i) => (
            <div key={i} className="card p-5 animate-pulse">
              <div className="h-4 bg-warm-300 rounded w-24 mb-3" />
              <div className="h-8 bg-warm-300 rounded w-16" />
            </div>
          ))}
        </div>
      ) : stats ? (
        <>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <StatCard label="Total Users" value={stats.users?.total || 0} icon={Users} sub={`${stats.users?.new_today || 0} new today`} color="bg-blue-100 text-blue-600" />
            <StatCard label="Active Users" value={stats.users?.active || 0} icon={UserPlus} color="bg-green-100 text-green-600" />
            <StatCard label="Total Posts" value={stats.posts?.total || 0} icon={FileText} sub={`${stats.posts?.new_today || 0} new today`} color="bg-purple-100 text-purple-600" />
            <StatCard label="Flagged Posts" value={stats.posts?.flagged || 0} icon={Shield} color="bg-red-100 text-red-600" />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <StatCard label="Pending Flags" value={stats.moderation?.pending_flags || 0} icon={Shield} color="bg-yellow-100 text-yellow-600" />
            <StatCard label="Pending Appeals" value={stats.appeals?.pending || 0} icon={Scale} color="bg-orange-100 text-orange-600" />
            <StatCard label="Pending Reports" value={stats.reports?.pending || 0} icon={Flag} color="bg-pink-100 text-pink-600" />
            <StatCard label="Banned Users" value={stats.users?.banned || 0} icon={TrendingDown} color="bg-red-100 text-red-600" />
          </div>

          {/* Charts */}
          {growth && (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
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
          <div className="mt-6 card p-5">
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
