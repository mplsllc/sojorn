// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import SelectionBar from '@/components/SelectionBar';
import { api } from '@/lib/api';
import { statusColor, formatDate, truncate } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Search, ChevronLeft, ChevronRight, Ban, CheckCircle, PauseCircle, Trash2 } from 'lucide-react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';

export default function UsersPage() {
  const searchParams = useSearchParams();
  const [users, setUsers] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [sort, setSort] = useState('newest');
  const [offset, setOffset] = useState(0);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkLoading, setBulkLoading] = useState(false);
  const limit = 25;

  useEffect(() => {
    const urlStatus = searchParams.get('status');
    if (urlStatus) setStatusFilter(urlStatus);
  }, []);

  const fetchUsers = () => {
    setLoading(true);
    api.listUsers({
      limit,
      offset,
      search: search || undefined,
      status: statusFilter || undefined,
      role: roleFilter || undefined,
      sort: sort || undefined,
    })
      .then((data) => { setUsers(data.users); setTotal(data.total); })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchUsers(); }, [offset, statusFilter, roleFilter, sort]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchUsers();
  };

  const toggleSelect = (id: string) => {
    setSelected((prev) => { const s = new Set(prev); s.has(id) ? s.delete(id) : s.add(id); return s; });
  };
  const toggleAll = () => {
    if (selected.size === users.length) setSelected(new Set());
    else setSelected(new Set(users.map((u) => u.id)));
  };

  const handleBulkAction = async (action: string) => {
    setBulkLoading(true);
    try {
      await api.bulkUpdateUsers(Array.from(selected), action, 'Bulk admin action');
      setSelected(new Set());
      fetchUsers();
    } catch (e: any) {
      alert(`Bulk action failed: ${e.message}`);
    }
    setBulkLoading(false);
  };

  const handleBanUser = async (userId: string) => {
    if (!confirm('Are you sure you want to ban this user?')) return;
    try {
      await api.bulkUpdateUsers([userId], 'ban', 'Admin quick action');
      fetchUsers();
    } catch (e: any) {
      alert(`Ban failed: ${e.message}`);
    }
  };

  const handleDeleteUser = async (userId: string) => {
    if (!confirm('Are you sure you want to permanently delete this user? This cannot be undone.')) return;
    try {
      await api.hardDeleteUser(userId);
      fetchUsers();
    } catch (e: any) {
      alert(`Delete failed: ${e.message}`);
    }
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Users</h1>
          <p className="text-sm text-gray-500 mt-1">{total} total users</p>
        </div>
      </div>

      {/* Filters */}
      <div className="card p-4 mb-4 flex flex-wrap gap-3 items-center">
        <form onSubmit={handleSearch} className="flex-1 min-w-[200px] relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            className="input pl-10"
            placeholder="Search by handle, name, or email..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </form>
        <select className="input w-auto" value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setOffset(0); }}>
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="pending">Pending</option>
          <option value="suspended">Suspended</option>
          <option value="banned">Banned</option>
          <option value="deactivated">Deactivated</option>
        </select>
        <select className="input w-auto" value={roleFilter} onChange={(e) => { setRoleFilter(e.target.value); setOffset(0); }}>
          <option value="">All Roles</option>
          <option value="user">User</option>
          <option value="moderator">Moderator</option>
          <option value="admin">Admin</option>
        </select>
        <select className="input w-auto" value={sort} onChange={(e) => { setSort(e.target.value); setOffset(0); }}>
          <option value="newest">Newest</option>
          <option value="oldest">Oldest</option>
          <option value="most_strikes">Most Strikes</option>
          <option value="handle_az">Handle A-Z</option>
        </select>
      </div>

      <SelectionBar
        count={selected.size}
        total={users.length}
        onSelectAll={() => setSelected(new Set(users.map((u) => u.id)))}
        onClearSelection={() => setSelected(new Set())}
        loading={bulkLoading}
        actions={[
          { label: 'Activate', action: 'activate', color: 'bg-green-50 text-green-700 hover:bg-green-100', icon: <CheckCircle className="w-3.5 h-3.5" /> },
          { label: 'Suspend', action: 'suspend', confirm: true, color: 'bg-yellow-50 text-yellow-700 hover:bg-yellow-100', icon: <PauseCircle className="w-3.5 h-3.5" /> },
          { label: 'Ban', action: 'ban', confirm: true, color: 'bg-red-100 text-red-800 hover:bg-red-200', icon: <Ban className="w-3.5 h-3.5" /> },
          { label: 'Delete', action: 'delete', confirm: true, color: 'bg-red-200 text-red-900 hover:bg-red-300', icon: <Trash2 className="w-3.5 h-3.5" /> },
        ]}
        onAction={handleBulkAction}
      />

      {/* Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-warm-200">
              <tr>
                <th className="table-header w-10">
                  <input type="checkbox" className="rounded border-gray-300" checked={users.length > 0 && selected.size === users.length} onChange={toggleAll} />
                </th>
                <th className="table-header">User</th>
                <th className="table-header">Email</th>
                <th className="table-header">Role</th>
                <th className="table-header">Status</th>
                <th className="table-header">Strikes</th>
                <th className="table-header">Joined</th>
                <th className="table-header">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-warm-300">
              {loading ? (
                [...Array(5)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(8)].map((_, j) => (
                      <td key={j} className="table-cell"><div className="h-4 bg-warm-300 rounded animate-pulse w-20" /></td>
                    ))}
                  </tr>
                ))
              ) : users.length === 0 ? (
                <tr><td colSpan={8} className="table-cell text-center text-gray-400 py-8">No users found</td></tr>
              ) : (
                users.map((user) => (
                  <tr key={user.id} className={`hover:bg-warm-50 transition-colors ${selected.has(user.id) ? 'bg-brand-50' : ''}`}>
                    <td className="table-cell">
                      <input type="checkbox" className="rounded border-gray-300" checked={selected.has(user.id)} onChange={() => toggleSelect(user.id)} />
                    </td>
                    <td className="table-cell">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 bg-brand-100 rounded-full flex items-center justify-center text-brand-600 text-xs font-bold">
                          {(user.handle || user.email || '?')[0].toUpperCase()}
                        </div>
                        <div>
                          <p className="font-medium text-gray-900">{user.display_name || user.handle || '—'}</p>
                          <p className="text-xs text-gray-400">@{user.handle || '—'}</p>
                        </div>
                      </div>
                    </td>
                    <td className="table-cell text-gray-500">{truncate(user.email || '', 25)}</td>
                    <td className="table-cell">
                      <span className={`badge ${user.role === 'admin' ? 'bg-purple-100 text-purple-700' : user.role === 'moderator' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600'}`}>
                        {user.role || 'user'}
                      </span>
                    </td>
                    <td className="table-cell">
                      <span className={`badge ${statusColor(user.status)}`}>{user.status}</span>
                    </td>
                    <td className="table-cell">{user.strikes ?? 0}</td>
                    <td className="table-cell text-gray-500">{formatDate(user.created_at)}</td>
                    <td className="table-cell">
                      <div className="flex items-center gap-2">
                        <Link href={`/users/${user.id}`} className="text-brand-500 hover:text-brand-700 text-sm font-medium">
                          View
                        </Link>
                        <button
                          type="button"
                          onClick={() => handleBanUser(user.id)}
                          className="text-yellow-600 hover:text-yellow-800 text-sm font-medium"
                          title="Ban user"
                        >
                          <Ban className="w-3.5 h-3.5" />
                        </button>
                        <button
                          type="button"
                          onClick={() => handleDeleteUser(user.id)}
                          className="text-red-600 hover:text-red-800 text-sm font-medium"
                          title="Delete user"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
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
            Showing {offset + 1}–{Math.min(offset + limit, total)} of {total}
          </p>
          <div className="flex gap-2">
            <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - limit))}>
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset + limit >= total} onClick={() => setOffset(offset + limit)}>
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </AdminShell>
  );
}
