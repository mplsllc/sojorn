// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDate, truncate } from '@/lib/utils';
import { ChevronLeft, ChevronRight, Search, Shield, ShieldOff, MessageSquare, Users, Building2, Pin, PinOff } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';

type Neighborhood = {
  id: string;
  name: string;
  city: string;
  state: string;
  zip_code: string;
  group_name: string;
  member_count: number;
  admin_count: number;
  board_post_count: number;
  group_post_count: number;
  created_at: string;
};

type NeighborhoodAdmin = {
  user_id: string;
  role: 'owner' | 'admin' | 'member';
  handle: string;
  display_name: string;
  avatar_url: string;
  joined_at: string;
};

export default function NeighborhoodsPage() {
  const [items, setItems] = useState<Neighborhood[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [zip, setZip] = useState('');
  const [state, setState] = useState('');
  const [sort, setSort] = useState<'name' | 'zip' | 'state' | 'members' | 'created'>('name');
  const [order, setOrder] = useState<'asc' | 'desc'>('asc');
  const [offset, setOffset] = useState(0);
  const [selected, setSelected] = useState<Neighborhood | null>(null);
  const [boardEntries, setBoardEntries] = useState<any[]>([]);
  const [boardLoading, setBoardLoading] = useState(false);
  const [boardSearch, setBoardSearch] = useState('');
  const [adminUserId, setAdminUserId] = useState('');
  const [admins, setAdmins] = useState<NeighborhoodAdmin[]>([]);
  const [adminLoading, setAdminLoading] = useState(false);
  const limit = 25;

  const selectedStats = useMemo(() => {
    if (!selected) return null;
    return [
      { label: 'Members', value: selected.member_count, icon: <Users className="w-4 h-4" /> },
      { label: 'Group Admins', value: selected.admin_count, icon: <Shield className="w-4 h-4" /> },
      { label: 'Board Posts', value: selected.board_post_count, icon: <MessageSquare className="w-4 h-4" /> },
      { label: 'Group Posts', value: selected.group_post_count, icon: <Building2 className="w-4 h-4" /> },
    ];
  }, [selected]);

  const fetchNeighborhoods = () => {
    setLoading(true);
    api
      .listNeighborhoods({ limit, offset, search: search || undefined, zip: zip || undefined, state: state || undefined, sort, order })
      .then((data) => {
        setItems(data.neighborhoods || []);
        setTotal(data.total || 0);
      })
      .finally(() => setLoading(false));
  };

  const fetchBoardEntries = (id: string, searchTerm = '') => {
    setBoardLoading(true);
    api
      .listNeighborhoodBoardEntries(id, { limit: 20, offset: 0, search: searchTerm || undefined })
      .then((data) => setBoardEntries(data.entries || []))
      .finally(() => setBoardLoading(false));
  };

  const fetchNeighborhoodAdmins = (id: string) => {
    setAdminLoading(true);
    api
      .listNeighborhoodAdmins(id)
      .then((data) => setAdmins(data.admins || []))
      .finally(() => setAdminLoading(false));
  };

  useEffect(() => {
    fetchNeighborhoods();
  }, [offset, sort, order]);

  const onSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchNeighborhoods();
  };

  const onSelectNeighborhood = (n: Neighborhood) => {
    setSelected(n);
    setBoardSearch('');
    fetchBoardEntries(n.id);
    fetchNeighborhoodAdmins(n.id);
  };

  const toggleBoardEntry = async (entryId: string, current: boolean) => {
    if (!selected) return;
    await api.updateNeighborhoodBoardEntry(selected.id, entryId, !current);
    fetchBoardEntries(selected.id, boardSearch);
    fetchNeighborhoods();
  };

  const updateAdmin = async (action: 'assign' | 'remove') => {
    if (!selected || !adminUserId.trim()) return;
    await api.setNeighborhoodAdmin(selected.id, adminUserId.trim(), action);
    setAdminUserId('');
    fetchNeighborhoods();
    fetchNeighborhoodAdmins(selected.id);
    fetchBoardEntries(selected.id, boardSearch);
  };

  const removeAdminById = async (userId: string) => {
    if (!selected || !userId) return;
    await api.setNeighborhoodAdmin(selected.id, userId, 'remove');
    fetchNeighborhoods();
    fetchNeighborhoodAdmins(selected.id);
  };

  const toggleBoardPin = async (entryId: string, current: boolean) => {
    if (!selected) return;
    await api.pinNeighborhoodBoardEntry(selected.id, entryId, !current);
    fetchBoardEntries(selected.id, boardSearch);
  };

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Neighborhoods</h1>
        <p className="text-sm text-gray-500 mt-1">Search, organize, and moderate neighborhood communities by name and ZIP.</p>
      </div>

      <div className="card p-4 mb-4 flex flex-wrap gap-3 items-center">
        <form onSubmit={onSearch} className="flex-1 min-w-[220px] relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            className="input pl-10"
            placeholder="Search neighborhood, city, state, ZIP..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </form>
        <input
          className="input w-32"
          placeholder="State"
          value={state}
          onChange={(e) => setState(e.target.value)}
        />
        <input
          className="input w-32"
          placeholder="ZIP"
          value={zip}
          onChange={(e) => setZip(e.target.value)}
        />
        <select className="input w-auto" value={sort} onChange={(e) => setSort(e.target.value as any)}>
          <option value="name">Sort: Name</option>
          <option value="state">Sort: State</option>
          <option value="zip">Sort: ZIP</option>
          <option value="members">Sort: Members</option>
          <option value="created">Sort: Created</option>
        </select>
        <select className="input w-auto" value={order} onChange={(e) => setOrder(e.target.value as any)}>
          <option value="asc">Asc</option>
          <option value="desc">Desc</option>
        </select>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-[1.4fr,1fr] gap-4">
        <div className="card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-warm-200">
                <tr>
                  <th className="table-header">Neighborhood</th>
                  <th className="table-header">State</th>
                  <th className="table-header">ZIP</th>
                  <th className="table-header">Members</th>
                  <th className="table-header">Admins</th>
                  <th className="table-header">Board</th>
                  <th className="table-header">Group</th>
                  <th className="table-header">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-warm-300">
                {loading ? (
                  [...Array(6)].map((_, i) => (
                    <tr key={i}>{[...Array(8)].map((__, j) => <td key={j} className="table-cell"><div className="h-4 bg-warm-300 rounded animate-pulse w-20" /></td>)}</tr>
                  ))
                ) : items.length === 0 ? (
                  <tr><td colSpan={8} className="table-cell text-center text-gray-400 py-8">No neighborhoods found</td></tr>
                ) : (
                  items.map((n) => (
                    <tr key={n.id} className={`hover:bg-warm-50 cursor-pointer ${selected?.id === n.id ? 'bg-brand-50' : ''}`} onClick={() => onSelectNeighborhood(n)}>
                      <td className="table-cell">
                        <div>
                          <p className="font-medium text-gray-900">{n.name}</p>
                          <p className="text-xs text-gray-500">{truncate(n.city, 25)}</p>
                        </div>
                      </td>
                      <td className="table-cell text-gray-600">{n.state || '—'}</td>
                      <td className="table-cell">{n.zip_code || '—'}</td>
                      <td className="table-cell">{n.member_count}</td>
                      <td className="table-cell">{n.admin_count}</td>
                      <td className="table-cell">{n.board_post_count}</td>
                      <td className="table-cell">{n.group_post_count}</td>
                      <td className="table-cell text-gray-500 text-xs">{formatDate(n.created_at)}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
          <div className="border-t border-warm-300 px-4 py-3 flex items-center justify-between">
            <p className="text-sm text-gray-500">Showing {Math.min(offset + 1, total)}–{Math.min(offset + limit, total)} of {total}</p>
            <div className="flex gap-2">
              <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - limit))}><ChevronLeft className="w-4 h-4" /></button>
              <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset + limit >= total} onClick={() => setOffset(offset + limit)}><ChevronRight className="w-4 h-4" /></button>
            </div>
          </div>
        </div>

        <div className="card p-4 min-h-[300px]">
          {!selected ? (
            <p className="text-sm text-gray-500">Select a neighborhood to manage admins and board content.</p>
          ) : (
            <div className="space-y-4">
              <div>
                <h2 className="text-lg font-semibold text-gray-900">{selected.name}</h2>
                <p className="text-sm text-gray-500">{selected.city}, {selected.state} {selected.zip_code ? `· ${selected.zip_code}` : ''}</p>
              </div>

              <div className="grid grid-cols-2 gap-2">
                {selectedStats?.map((stat) => (
                  <div key={stat.label} className="rounded-lg border border-warm-300 p-2 bg-warm-100">
                    <div className="flex items-center gap-2 text-gray-500 text-xs">{stat.icon}<span>{stat.label}</span></div>
                    <p className="text-lg font-semibold text-gray-900">{stat.value}</p>
                  </div>
                ))}
              </div>

              <div className="border border-warm-300 rounded-lg p-3 bg-warm-50">
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-500 mb-2">Neighborhood Admins</p>
                <div className="flex gap-2">
                  <input className="input" placeholder="User ID to assign/remove" value={adminUserId} onChange={(e) => setAdminUserId(e.target.value)} />
                  <button className="btn-primary text-sm" onClick={() => updateAdmin('assign')}><Shield className="w-4 h-4" />Assign</button>
                  <button className="btn-secondary text-sm" onClick={() => updateAdmin('remove')}><ShieldOff className="w-4 h-4" />Remove</button>
                </div>
                <div className="mt-3 rounded-lg border border-warm-300 bg-white overflow-hidden">
                  <div className="px-3 py-2 border-b border-warm-200 text-xs font-semibold text-gray-600">Current Moderators</div>
                  {adminLoading ? (
                    <p className="px-3 py-2 text-xs text-gray-500">Loading moderators…</p>
                  ) : admins.length === 0 ? (
                    <p className="px-3 py-2 text-xs text-gray-500">No admins found for this neighborhood.</p>
                  ) : (
                    admins.map((mod) => (
                      <div key={mod.user_id} className="px-3 py-2 border-b border-warm-100 last:border-0 flex items-center justify-between gap-2">
                        <div>
                          <p className="text-sm font-medium text-gray-800">{mod.display_name || mod.handle || mod.user_id}</p>
                          <p className="text-xs text-gray-500">@{mod.handle || 'unknown'} · {mod.role}</p>
                        </div>
                        {mod.role === 'admin' && (
                          <button className="text-xs text-red-600 hover:text-red-700 font-medium" onClick={() => removeAdminById(mod.user_id)}>
                            Remove
                          </button>
                        )}
                      </div>
                    ))
                  )}
                </div>
              </div>

              <div className="border border-warm-300 rounded-lg overflow-hidden">
                <div className="p-3 bg-warm-100 border-b border-warm-300 flex items-center justify-between">
                  <p className="text-sm font-semibold text-gray-700">Board Moderation</p>
                  <form
                    className="relative"
                    onSubmit={(e) => {
                      e.preventDefault();
                      if (selected) fetchBoardEntries(selected.id, boardSearch);
                    }}
                  >
                    <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
                    <input className="input h-8 pl-7 text-xs" placeholder="Search posts" value={boardSearch} onChange={(e) => setBoardSearch(e.target.value)} />
                  </form>
                </div>
                <div className="max-h-80 overflow-y-auto">
                  {boardLoading ? (
                    <p className="p-3 text-xs text-gray-500">Loading board entries…</p>
                  ) : boardEntries.length === 0 ? (
                    <p className="p-3 text-xs text-gray-500">No board entries in this neighborhood.</p>
                  ) : (
                    boardEntries.map((entry) => (
                      <div key={entry.id} className="p-3 border-b border-warm-200 last:border-0">
                        <p className="text-sm text-gray-900 line-clamp-2">{entry.body}</p>
                        <div className="mt-1 text-xs text-gray-500 flex items-center justify-between">
                          <span>@{entry.author?.handle || 'unknown'} · {entry.topic || 'community'}</span>
                          <span>{entry.upvotes || 0}↑ · {entry.reply_count || 0} replies</span>
                        </div>
                        <div className="mt-2">
                          <div className="flex items-center gap-3">
                            <button
                              className={`text-xs font-medium ${entry.is_active ? 'text-red-600 hover:text-red-700' : 'text-green-600 hover:text-green-700'}`}
                              onClick={() => toggleBoardEntry(entry.id, !!entry.is_active)}
                            >
                              {entry.is_active ? 'Hide post' : 'Restore post'}
                            </button>
                            <button
                              className={`text-xs font-medium inline-flex items-center gap-1 ${entry.is_pinned ? 'text-orange-600 hover:text-orange-700' : 'text-brand-600 hover:text-brand-700'}`}
                              onClick={() => toggleBoardPin(entry.id, !!entry.is_pinned)}
                            >
                              {entry.is_pinned ? <PinOff className="w-3.5 h-3.5" /> : <Pin className="w-3.5 h-3.5" />}
                              {entry.is_pinned ? 'Unpin' : 'Pin'}
                            </button>
                          </div>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </AdminShell>
  );
}
